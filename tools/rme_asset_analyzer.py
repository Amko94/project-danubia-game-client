#!/usr/bin/env python3
"""Inspect Tibia 8.00 DAT/SPR and RME OTB material data.

The script is intentionally dependency-light (Pillow is only needed by future
image/report commands) so it can also be reused when new custom assets arrive.
"""

from __future__ import annotations

import argparse
import copy
import json
import re
import shutil
import struct
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
import xml.etree.ElementTree as ET


NODE_START = 0xFE
NODE_END = 0xFF
ESCAPE = 0xFD


@dataclass
class OTBItem:
    category: int
    flags: int
    server_id: int | None = None
    client_id: int | None = None
    name: str | None = None
    sprite_hash: str | None = None


@dataclass
class DatThing:
    client_id: int
    attributes: list[int]
    ground_speed: int | None
    width: int
    height: int
    layers: int
    pattern_x: int
    pattern_y: int
    pattern_z: int
    animation_phases: int
    sprites: list[int]


def _u16(data: bytes, offset: int) -> tuple[int, int]:
    return struct.unpack_from("<H", data, offset)[0], offset + 2


def _u32(data: bytes, offset: int) -> tuple[int, int]:
    return struct.unpack_from("<I", data, offset)[0], offset + 4


def _read_otb_node(data: bytes, offset: int) -> tuple[bytes, list[bytes], int]:
    if data[offset] != NODE_START:
        raise ValueError(f"Expected OTB node start at {offset:#x}")
    offset += 1
    payload = bytearray()
    children: list[bytes] = []
    while offset < len(data):
        value = data[offset]
        offset += 1
        if value == ESCAPE:
            if offset >= len(data):
                raise ValueError("Dangling OTB escape byte")
            payload.append(data[offset])
            offset += 1
        elif value == NODE_START:
            child_payload, grand_children, offset = _read_otb_node(data, offset - 1)
            if grand_children:
                raise ValueError("Unexpected grandchildren in items.otb")
            children.append(child_payload)
        elif value == NODE_END:
            return bytes(payload), children, offset
        else:
            payload.append(value)
    raise ValueError("Unterminated OTB node")


def parse_otb(path: Path) -> tuple[dict, list[OTBItem]]:
    data = path.read_bytes()
    if len(data) < 6 or data[:4] != b"\0\0\0\0":
        raise ValueError(f"Invalid items.otb signature: {path}")
    root, children, end = _read_otb_node(data, 4)
    if end != len(data):
        raise ValueError(f"Trailing bytes in {path}: {len(data) - end}")
    if len(root) < 6 or root[0] != 0 or root[1:5] != b"\0\0\0\0":
        raise ValueError(f"Invalid items.otb root: {path}")

    root_info: dict[str, int | str] = {}
    pos = 5
    while pos < len(root):
        attr = root[pos]
        pos += 1
        length, pos = _u16(root, pos)
        value = root[pos : pos + length]
        pos += length
        if attr == 1 and length >= 140:
            major, minor, build = struct.unpack_from("<III", value)
            description = value[12:140].split(b"\0", 1)[0].decode("latin1")
            root_info.update(major=major, minor=minor, build=build, description=description)

    items: list[OTBItem] = []
    for payload in children:
        if len(payload) < 5:
            continue
        category = payload[0]
        flags = struct.unpack_from("<I", payload, 1)[0]
        item = OTBItem(category=category, flags=flags)
        pos = 5
        while pos + 3 <= len(payload):
            attr = payload[pos]
            pos += 1
            length, pos = _u16(payload, pos)
            value = payload[pos : pos + length]
            pos += length
            if len(value) != length:
                raise ValueError(f"Truncated OTB item attribute {attr}")
            if attr == 16 and length >= 2:
                item.server_id = struct.unpack_from("<H", value)[0]
            elif attr == 17 and length >= 2:
                item.client_id = struct.unpack_from("<H", value)[0]
            elif attr == 18:
                item.name = value.decode("latin1")
            elif attr == 32:
                item.sprite_hash = value.hex()
        items.append(item)
    return root_info, items


def _dat_attr_payload_size(raw_attr: int, client_version: int) -> int:
    attr = raw_attr
    if 780 <= client_version < 860:
        if raw_attr == 8:  # chargeable flag, no payload
            return 0
        if raw_attr > 8:
            attr -= 1
    if attr in {0, 8, 9, 25, 28, 29, 32, 34}:
        return 2
    if attr in {21, 24}:
        return 4
    if attr == 33:
        raise ValueError("Market attribute is not valid in a Tibia 8.00 DAT")
    if attr == 38:
        return 16
    return 0


def parse_dat_items(path: Path, client_version: int = 800) -> tuple[dict, list[DatThing]]:
    data = path.read_bytes()
    if len(data) < 12:
        raise ValueError(f"DAT is too short: {path}")
    signature, item_count, creature_count, effect_count, missile_count = struct.unpack_from("<IHHHH", data)
    pos = 12
    categories = [item_count, creature_count, effect_count, missile_count]
    things: list[DatThing] = []
    for category, count in enumerate(categories):
        first_id = 100 if category == 0 else 1
        for client_id in range(first_id, count + 1):
            attrs: list[int] = []
            ground_speed = None
            while True:
                if pos >= len(data):
                    raise ValueError(f"Unexpected DAT EOF at category {category}, id {client_id}")
                raw_attr = data[pos]
                pos += 1
                if raw_attr == 0xFF:
                    break
                attrs.append(raw_attr)
                payload_size = _dat_attr_payload_size(raw_attr, client_version)
                if raw_attr == 0 and payload_size == 2:
                    ground_speed = struct.unpack_from("<H", data, pos)[0]
                pos += payload_size

            width = data[pos]
            height = data[pos + 1]
            pos += 2
            if width > 1 or height > 1:
                pos += 1  # exact/real size
            layers, pattern_x, pattern_y = data[pos : pos + 3]
            pos += 3
            if client_version >= 755:
                pattern_z = data[pos]
                pos += 1
            else:
                pattern_z = 1
            animation_phases = data[pos]
            pos += 1
            sprite_count = width * height * layers * pattern_x * pattern_y * pattern_z * animation_phases
            sprite_width = 4 if client_version >= 960 else 2
            fmt = f"<{sprite_count}{'I' if sprite_width == 4 else 'H'}"
            byte_count = sprite_count * sprite_width
            sprites = list(struct.unpack_from(fmt, data, pos)) if sprite_count else []
            pos += byte_count
            if category == 0:
                things.append(
                    DatThing(
                        client_id=client_id,
                        attributes=attrs,
                        ground_speed=ground_speed,
                        width=width,
                        height=height,
                        layers=layers,
                        pattern_x=pattern_x,
                        pattern_y=pattern_y,
                        pattern_z=pattern_z,
                        animation_phases=animation_phases,
                        sprites=sprites,
                    )
                )
    if pos != len(data):
        raise ValueError(f"DAT parser ended with {len(data) - pos} trailing bytes")
    return {
        "signature": signature,
        "items": item_count,
        "creatures": creature_count,
        "effects": effect_count,
        "missiles": missile_count,
    }, things


def command_summary(args: argparse.Namespace) -> None:
    dat_info, dat_items = parse_dat_items(args.dat)
    otb_info, otb_items = parse_otb(args.otb)
    mapped = [item for item in otb_items if item.server_id is not None and item.client_id is not None]
    new_mapped = [item for item in mapped if item.client_id > args.old_last_client_id]
    dat_by_id = {item.client_id: item for item in dat_items}
    result = {
        "dat": dat_info,
        "otb": otb_info,
        "otb_items": len(otb_items),
        "mapped_items": len(mapped),
        "server_id_range": [min(i.server_id for i in mapped), max(i.server_id for i in mapped)],
        "client_id_range": [min(i.client_id for i in mapped), max(i.client_id for i in mapped)],
        "new_mapped_items": len(new_mapped),
        "new_server_id_range": [
            min(i.server_id for i in new_mapped),
            max(i.server_id for i in new_mapped),
        ] if new_mapped else None,
        "new_dat_attribute_counts": {
            "ground": sum(0 in dat_by_id[i.client_id].attributes for i in new_mapped),
            "ground_border": sum(1 in dat_by_id[i.client_id].attributes for i in new_mapped),
            "on_bottom": sum(2 in dat_by_id[i.client_id].attributes for i in new_mapped),
            "on_top": sum(3 in dat_by_id[i.client_id].attributes for i in new_mapped),
            "not_walkable": sum(13 in dat_by_id[i.client_id].attributes for i in new_mapped),
            "hangable": sum(18 in dat_by_id[i.client_id].attributes for i in new_mapped),
        },
    }
    print(json.dumps(result, indent=2))
    if args.output:
        args.output.write_text(json.dumps([asdict(item) for item in new_mapped], indent=2), encoding="utf-8")


def _source_to_target_mapper(source_items: list[OTBItem], target_items: list[OTBItem], new_start: int):
    target_by_hash: dict[str, list[OTBItem]] = {}
    for item in target_items:
        if item.sprite_hash and item.client_id is not None:
            target_by_hash.setdefault(item.sprite_hash, []).append(item)

    source_by_hash: dict[str, list[OTBItem]] = {}
    for item in source_items:
        if item.sprite_hash and item.client_id is not None:
            source_by_hash.setdefault(item.sprite_hash, []).append(item)
    source_by_server = {item.server_id: item for item in source_items if item.server_id is not None}
    source_by_client = {item.client_id: item for item in source_items if item.client_id is not None}

    # Preserve distinct items that deliberately share the same visual (doors,
    # open/closed variants, invisible helpers). Exact unchanged IDs are paired
    # first; remaining occurrences are paired in ID order.
    resolved: dict[int, int] = {}
    for sprite_hash, sources in source_by_hash.items():
        targets = sorted(target_by_hash.get(sprite_hash, []), key=lambda item: item.client_id)
        if not targets:
            continue
        sources = sorted(sources, key=lambda item: item.client_id)
        remaining_targets = {item.client_id for item in targets}
        remaining_sources: list[OTBItem] = []
        for source in sources:
            if source.client_id in remaining_targets:
                resolved[source.client_id] = source.client_id
                remaining_targets.remove(source.client_id)
            else:
                remaining_sources.append(source)
        ordered_targets = sorted(remaining_targets)
        if len(remaining_sources) == len(ordered_targets):
            for source, target_id in zip(remaining_sources, ordered_targets):
                resolved[source.client_id] = target_id
        else:
            available = set(ordered_targets)
            for source in remaining_sources:
                pool = available or {item.client_id for item in targets}
                target_id = min(pool, key=lambda value: abs(value - source.client_id))
                resolved[source.client_id] = target_id
                available.discard(target_id)

    def source_client_to_target(client_id: int, prefer_new: bool = True) -> int | None:
        source = source_by_client.get(client_id)
        if not source or not source.sprite_hash:
            return None
        if client_id in resolved:
            mapped = resolved[client_id]
            if not prefer_new or mapped >= new_start:
                return mapped
        candidates = target_by_hash.get(source.sprite_hash, [])
        if not candidates:
            return None
        if prefer_new:
            new_candidates = [item for item in candidates if item.client_id >= new_start]
            if new_candidates:
                candidates = new_candidates
        exact = next((item for item in candidates if item.client_id == client_id), None)
        if exact:
            return exact.client_id
        return min(candidates, key=lambda item: abs(item.client_id - client_id)).client_id

    def source_server_to_target(server_id: int, prefer_new: bool = True) -> int | None:
        source = source_by_server.get(server_id)
        if not source or source.client_id is None:
            return None
        return source_client_to_target(source.client_id, prefer_new=prefer_new)

    return source_server_to_target, source_client_to_target


def _expand_ids(element: ET.Element) -> list[int]:
    if "id" in element.attrib:
        return [int(element.attrib["id"])]
    if "fromid" in element.attrib:
        first = int(element.attrib["fromid"])
        last = int(element.attrib.get("toid", first))
        return list(range(first, last + 1))
    return []


def _compress_ids(ids: set[int]) -> list[tuple[int, int]]:
    values = sorted(ids)
    if not values:
        return []
    ranges: list[tuple[int, int]] = []
    first = previous = values[0]
    for value in values[1:]:
        if value == previous + 1:
            previous = value
            continue
        ranges.append((first, previous))
        first = previous = value
    ranges.append((first, previous))
    return ranges


def _set_item_range(element: ET.Element, first: int, last: int) -> None:
    element.attrib.pop("id", None)
    element.attrib.pop("fromid", None)
    element.attrib.pop("toid", None)
    if first == last:
        element.set("id", str(first))
    else:
        element.set("fromid", str(first))
        element.set("toid", str(last))


def _transform_element(
    source: ET.Element,
    map_server,
    map_client,
) -> list[ET.Element]:
    # Range-bearing <item> nodes need expansion because imported target IDs are
    # no longer contiguous in the same way as the source client.
    if source.tag == "item" and ("id" in source.attrib or "fromid" in source.attrib):
        mapped = {value for source_id in _expand_ids(source) if (value := map_server(source_id)) is not None}
        result: list[ET.Element] = []
        for first, last in _compress_ids(mapped):
            clone = ET.Element(source.tag, dict(source.attrib))
            _set_item_range(clone, first, last)
            clone.text = source.text
            clone.tail = source.tail
            for child in source:
                clone.extend(_transform_element(child, map_server, map_client))
            result.append(clone)
        return result

    clone = ET.Element(source.tag, dict(source.attrib))
    clone.text = source.text
    clone.tail = source.tail

    def map_attr(name: str, mapper=map_server) -> bool:
        if name not in clone.attrib:
            return True
        mapped = mapper(int(clone.attrib[name]))
        if mapped is None:
            return False
        clone.set(name, str(mapped))
        return True

    if source.tag == "brush":
        if not map_attr("server_lookid"):
            clone.attrib.pop("server_lookid", None)
        if not map_attr("lookid", map_client):
            clone.attrib.pop("lookid", None)
    elif source.tag in {"door", "optional", "match_item", "carpet"}:
        if not map_attr("id"):
            return []
    elif source.tag == "borderitem":
        if not map_attr("item"):
            return []
    elif source.tag == "replace_item":
        if not map_attr("id") or not map_attr("with"):
            return []
    elif source.tag == "border" and "ground_equivalent" in source.attrib:
        if not map_attr("ground_equivalent"):
            clone.attrib.pop("ground_equivalent", None)

    for child in source:
        clone.extend(_transform_element(child, map_server, map_client))
    return [clone]


def _write_material_file(path: Path, children: list[ET.Element], note: str) -> None:
    root = ET.Element("materials")
    root.append(ET.Comment(f" {note} "))
    root.extend(children)
    ET.indent(root, space="\t")
    tree = ET.ElementTree(root)
    tree.write(path, encoding="utf-8", xml_declaration=True, short_empty_elements=True)


def _referenced_target_ids(element: ET.Element) -> set[int]:
    ids: set[int] = set()
    for node in element.iter():
        if node.tag == "item":
            ids.update(_expand_ids(node))
        elif node.tag == "borderitem" and "item" in node.attrib:
            ids.add(int(node.attrib["item"]))
        elif node.tag in {"door", "optional", "match_item", "carpet"} and "id" in node.attrib:
            ids.add(int(node.attrib["id"]))
        elif node.tag == "replace_item":
            for attr in ("id", "with"):
                if attr in node.attrib:
                    ids.add(int(node.attrib[attr]))
    return ids


def _item_reference_count(element: ET.Element) -> int:
    count = 0
    for node in element.iter():
        if node.tag == "item":
            count += len(_expand_ids(node))
        elif node.tag == "borderitem" and "item" in node.attrib:
            count += 1
        elif node.tag in {"door", "optional", "match_item", "carpet"} and "id" in node.attrib:
            count += 1
        elif node.tag == "replace_item":
            count += sum(attr in node.attrib for attr in ("id", "with"))
    return count


def _generate_missing_definitions(
    target_dir: Path,
    source_dir: Path,
    output_dir: Path,
    map_server,
    map_client,
    new_start: int,
) -> dict[str, dict[str, int]]:
    specs = {
        "borders.xml": ("border", "id", "generated-borders.xml"),
        "grounds.xml": ("brush", "name", "generated-grounds.xml"),
        "walls.xml": ("brush", "name", "generated-walls.xml"),
        "doodads.xml": ("brush", "name", "generated-doodads.xml"),
    }
    stats: dict[str, dict[str, int]] = {}
    available_border_ids: set[int] = set()
    for source_name, (tag, key, output_name) in specs.items():
        target_root = ET.parse(target_dir / source_name).getroot()
        source_root = ET.parse(source_dir / source_name).getroot()
        existing = {node.get(key) for node in target_root.findall(tag)}
        generated: list[ET.Element] = []
        skipped_incomplete = 0
        for node in source_root.findall(tag):
            if node.get(key) in existing:
                continue
            transformed = _transform_element(node, map_server, map_client)
            if not transformed:
                skipped_incomplete += 1
                continue
            candidate = transformed[0]
            refs = _referenced_target_ids(candidate)
            if tag != "border" and not any(item_id >= new_start for item_id in refs):
                continue
            if _item_reference_count(candidate) != _item_reference_count(node):
                skipped_incomplete += 1
                continue
            # Auto-borders must have every source edge; incomplete edge sets
            # create visibly broken terrain transitions and are not installed.
            if tag == "border" and len(candidate.findall("borderitem")) != len(node.findall("borderitem")):
                skipped_incomplete += 1
                continue
            if tag == "brush" and source_name == "grounds.xml":
                border_refs = {int(child.get("id")) for child in candidate.findall("border") if child.get("id")}
                if not border_refs.issubset(available_border_ids):
                    skipped_incomplete += 1
                    continue
            generated.append(candidate)

        if tag == "brush":
            known_brush_names = {
                node.get("name") for node in target_root.findall("brush") if node.get("name")
            }
            known_brush_names.update(node.get("name") for node in generated if node.get("name"))
            for brush in generated:
                for relation in list(brush):
                    if relation.tag in {"friend", "enemy"} and relation.get("name"):
                        if relation.get("name") not in known_brush_names and relation.get("name") != "all":
                            brush.remove(relation)
        _write_material_file(
            output_dir / output_name,
            generated,
            f"Generated from RME {source_dir.name}; source IDs translated by sprite hash.",
        )
        stats[output_name] = {"generated": len(generated), "skipped_incomplete": skipped_incomplete}
        if tag == "border":
            available_border_ids = {
                int(node.get("id")) for node in target_root.findall("border") if node.get("id")
            }
            available_border_ids.update(
                int(node.get("id")) for node in generated if node.get("id")
            )
    return stats


def _source_tileset_memberships(source_dir: Path, map_server, new_start: int) -> dict[str, set[int]]:
    result: dict[str, set[int]] = {}
    root = ET.parse(source_dir / "tilesets.xml").getroot()
    for tileset in root.findall("tileset"):
        ids: set[int] = set()
        for item in tileset.iter("item"):
            for source_id in _expand_ids(item):
                mapped = map_server(source_id)
                if mapped is not None and mapped >= new_start:
                    ids.add(mapped)
        if ids:
            result[tileset.get("name", "Unnamed")] = ids
    return result


def _generate_tilesets(
    output_path: Path,
    source_dir: Path,
    map_server,
    target_dat: dict[int, DatThing],
    source_items: list[OTBItem],
    target_items: list[OTBItem],
    new_start: int,
) -> dict[str, int]:
    memberships = _source_tileset_memberships(source_dir, map_server, new_start)
    all_new = {item.client_id for item in target_items if item.client_id is not None and item.client_id >= new_start}

    # DAT flags are authoritative even when an asset has no official 8.70
    # palette membership or its sprite is custom.
    memberships.setdefault("Grounds", set()).update(
        item_id for item_id in all_new if item_id in target_dat and 0 in target_dat[item_id].attributes
    )
    memberships.setdefault("Borders", set()).update(
        item_id for item_id in all_new if item_id in target_dat and 1 in target_dat[item_id].attributes
    )
    memberships.setdefault("Hangables", set()).update(
        item_id for item_id in all_new if item_id in target_dat and 18 in target_dat[item_id].attributes
    )

    source_hashes = {item.sprite_hash for item in source_items if item.sprite_hash}
    unmatched = {
        item.client_id
        for item in target_items
        if item.client_id is not None
        and item.client_id >= new_start
        and item.sprite_hash not in source_hashes
    }
    categorized = set().union(*memberships.values()) if memberships else set()
    uncategorized = all_new - categorized - unmatched
    if uncategorized:
        memberships["Unsorted"] = uncategorized
    if unmatched:
        memberships["Unmatched / Custom"] = unmatched

    root = ET.Element("materials")
    root.append(ET.Comment(" Generated semantic palettes for imported DAT items. "))
    preferred_order = ["Grounds", "Borders", "Walls", "Roofs", "Architecture"]
    names = [name for name in preferred_order if name in memberships]
    names.extend(sorted(name for name in memberships if name not in preferred_order))
    stats: dict[str, int] = {}
    for name in names:
        ids = memberships[name]
        if not ids:
            continue
        tileset = ET.SubElement(root, "tileset", {"name": f"New 8.10-8.70 - {name}"})
        raw = ET.SubElement(tileset, "raw")
        for first, last in _compress_ids(ids):
            item = ET.SubElement(raw, "item")
            _set_item_range(item, first, last)
        stats[name] = len(ids)
    ET.indent(root, space="\t")
    ET.ElementTree(root).write(output_path, encoding="utf-8", xml_declaration=True, short_empty_elements=True)
    return stats


def _install_material_includes(target_dir: Path, generated_names: list[str]) -> Path | None:
    materials = target_dir / "materials.xml"
    text = materials.read_text(encoding="utf-8-sig")
    missing = [name for name in generated_names if f'file="{name}"' not in text]
    if not missing:
        return None
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = target_dir / f"materials.xml.codex-backup-{stamp}"
    shutil.copy2(materials, backup)
    includes = "".join(f'\t<include file="{name}"/>\n' for name in missing)
    updated, replacements = re.subn(r"(?=</materials>\s*$)", includes, text, count=1)
    if replacements != 1:
        raise ValueError(f"Could not locate closing </materials> in {materials}")
    materials.write_text(updated, encoding="utf-8", newline="\n")
    return backup


def _reorder_material_includes(target_dir: Path) -> Path | None:
    """Load brush definitions before tilesets that reference those brushes."""
    materials = target_dir / "materials.xml"
    text = materials.read_text(encoding="utf-8-sig")
    order = [
        "borders.xml",
        "generated-borders.xml",
        "grounds.xml",
        "generated-grounds.xml",
        "walls.xml",
        "generated-walls.xml",
        "doodads.xml",
        "generated-doodads.xml",
        "tilesets.xml",
    ]
    kept_lines = [
        line for line in text.splitlines()
        if not re.fullmatch(r'<include file="[^"]+"\s*/>', line.strip())
    ]
    without_includes = "\n".join(kept_lines) + "\n"
    block = "".join(f'\t<include file="{name}"/>\n' for name in order if (target_dir / name).exists())
    updated, replacements = re.subn(r"(?=</materials>\s*$)", block, without_includes, count=1)
    if replacements != 1:
        raise ValueError(f"Could not locate closing </materials> in {materials}")
    if updated == text:
        return None
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = target_dir / f"materials.xml.codex-backup-order-{stamp}"
    shutil.copy2(materials, backup)
    materials.write_text(updated, encoding="utf-8", newline="\n")
    return backup


def command_generate(args: argparse.Namespace) -> None:
    target_dir = args.target_dir.resolve()
    source_dir = args.source_dir.resolve()
    output_dir = (args.output_dir or target_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    _, source_items = parse_otb(source_dir / "items.otb")
    _, target_items = parse_otb(target_dir / "items.otb")
    dat_info, dat_items = parse_dat_items(args.dat)
    target_dat = {item.client_id: item for item in dat_items}
    map_server, map_client = _source_to_target_mapper(source_items, target_items, args.new_start)

    definition_stats = _generate_missing_definitions(
        target_dir, source_dir, output_dir, map_server, map_client, args.new_start
    )
    generated_names = [
        "generated-borders.xml",
        "generated-grounds.xml",
        "generated-walls.xml",
        "generated-doodads.xml",
        "generated-tilesets.xml",
    ]
    tileset_stats = _generate_tilesets(
        output_dir / "generated-tilesets.xml",
        source_dir,
        map_server,
        target_dat,
        source_items,
        target_items,
        args.new_start,
    )
    backup = None
    if args.install:
        if output_dir != target_dir:
            for name in generated_names:
                shutil.copy2(output_dir / name, target_dir / name)
        backup = _install_material_includes(target_dir, generated_names)

    for name in generated_names:
        ET.parse(output_dir / name)
    result = {
        "dat": dat_info,
        "source": str(source_dir),
        "target": str(target_dir),
        "output": str(output_dir),
        "new_start": args.new_start,
        "definitions": definition_stats,
        "tilesets": tileset_stats,
        "installed": args.install,
        "materials_backup": str(backup) if backup else None,
    }
    print(json.dumps(result, indent=2))


def _xml_parser_with_comments() -> ET.XMLParser:
    return ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))


def _find_tileset(root: ET.Element, name: str) -> ET.Element | None:
    return next((node for node in root.findall("tileset") if node.get("name") == name), None)


def _ensure_tileset_group(tileset: ET.Element, tag: str) -> ET.Element:
    group = tileset.find(tag)
    if group is None:
        group = ET.SubElement(tileset, tag)
    return group


def _merge_item_ids(group: ET.Element, ids: set[int]) -> int:
    existing: set[int] = set()
    for item in group.findall("item"):
        existing.update(_expand_ids(item))
    new_ids = ids - existing
    for first, last in _compress_ids(new_ids):
        item = ET.SubElement(group, "item")
        _set_item_range(item, first, last)
    return len(new_ids)


def command_integrate(args: argparse.Namespace) -> None:
    target_dir = args.target_dir.resolve()
    source_dir = args.source_dir.resolve()
    _, source_items = parse_otb(source_dir / "items.otb")
    _, target_items = parse_otb(target_dir / "items.otb")
    _, dat_items = parse_dat_items(args.dat)
    dat_by_id = {item.client_id: item for item in dat_items}
    map_server, _ = _source_to_target_mapper(source_items, target_items, args.new_start)

    target_path = target_dir / "tilesets.xml"
    source_path = source_dir / "tilesets.xml"
    target_tree = ET.parse(target_path, parser=_xml_parser_with_comments())
    source_root = ET.parse(source_path).getroot()
    target_root = target_tree.getroot()

    brush_files = [
        "grounds.xml", "walls.xml", "doodads.xml",
        "generated-grounds.xml", "generated-walls.xml", "generated-doodads.xml",
    ]
    available_brushes: set[str] = set()
    for name in brush_files:
        path = target_dir / name
        if path.exists():
            available_brushes.update(
                node.get("name") for node in ET.parse(path).getroot().findall("brush") if node.get("name")
            )

    aliases = {
        "Architecture": "Buildings",
        "Beds": "Interior",
        "Signs": "Exterior",
        "Fluid Containers": "Containers",
        "Jewelry": "Trinkets",
        "Addon and Quest Items": "Trinkets",
        "Writeables": "Writables",
        "Borders": "Borders (full)",
    }
    skip_tilesets = {"Blank"}
    stats: dict[str, dict[str, int]] = {}

    for source_tileset in source_root.findall("tileset"):
        source_name = source_tileset.get("name", "Unnamed")
        if source_name in skip_tilesets:
            continue
        target_name = aliases.get(source_name, source_name)
        target_tileset = _find_tileset(target_root, target_name)
        if target_tileset is None:
            target_tileset = ET.SubElement(target_root, "tileset", {"name": target_name})
        tile_stats = stats.setdefault(target_name, {"brushes": 0, "items": 0})

        for source_group in source_tileset:
            if source_group.tag not in {"terrain", "doodad", "raw"}:
                continue
            target_group = _ensure_tileset_group(target_tileset, source_group.tag)
            existing_brushes = {
                node.get("name") for node in target_group.findall("brush") if node.get("name")
            }
            for brush in source_group.findall("brush"):
                brush_name = brush.get("name")
                if brush_name in available_brushes and brush_name not in existing_brushes:
                    ET.SubElement(target_group, "brush", {"name": brush_name})
                    existing_brushes.add(brush_name)
                    tile_stats["brushes"] += 1

            mapped_ids: set[int] = set()
            for item in source_group.findall("item"):
                for source_id in _expand_ids(item):
                    mapped = map_server(source_id)
                    if mapped is not None and mapped >= args.new_start:
                        mapped_ids.add(mapped)
            tile_stats["items"] += _merge_item_ids(target_group, mapped_ids)

    all_new = {
        item.client_id for item in target_items if item.client_id is not None and item.client_id >= args.new_start
    }
    authoritative_groups = {
        "Grounds": {item_id for item_id in all_new if item_id in dat_by_id and 0 in dat_by_id[item_id].attributes},
        "Borders (full)": {item_id for item_id in all_new if item_id in dat_by_id and 1 in dat_by_id[item_id].attributes},
        "Hangables": {item_id for item_id in all_new if item_id in dat_by_id and 18 in dat_by_id[item_id].attributes},
    }
    for tileset_name, ids in authoritative_groups.items():
        tileset = _find_tileset(target_root, tileset_name)
        if tileset is None:
            tileset = ET.SubElement(target_root, "tileset", {"name": tileset_name})
        added = _merge_item_ids(_ensure_tileset_group(tileset, "raw"), ids)
        entry = stats.setdefault(tileset_name, {"brushes": 0, "items": 0})
        entry["items"] += added

    # Cave assets are historically listed under Nature in the 8.70 files.
    # Mirror the clearly named generated brushes into Cave for practical use.
    cave = _find_tileset(target_root, "Cave")
    if cave is not None:
        cave_group = _ensure_tileset_group(cave, "doodad")
        existing = {node.get("name") for node in cave_group.findall("brush")}
        cave_names = sorted(
            name for name in available_brushes
            if name and ("cave" in name.lower() or "cave crystal" in name.lower())
        )
        for name in cave_names:
            if name not in existing:
                ET.SubElement(cave_group, "brush", {"name": name})
                existing.add(name)
                stats.setdefault("Cave", {"brushes": 0, "items": 0})["brushes"] += 1

    ET.indent(target_root, space="\t")
    backup = None
    if args.install:
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup = target_dir / f"tilesets.xml.codex-backup-{stamp}"
        shutil.copy2(target_path, backup)
        target_tree.write(target_path, encoding="utf-8", xml_declaration=False, short_empty_elements=True)

        materials = target_dir / "materials.xml"
        text = materials.read_text(encoding="utf-8-sig")
        updated = re.sub(r'^\s*<include file="generated-tilesets\.xml"/>\s*\r?\n?', "", text, flags=re.MULTILINE)
        if updated != text:
            material_backup = target_dir / f"materials.xml.codex-backup-integrate-{stamp}"
            shutil.copy2(materials, material_backup)
            materials.write_text(updated, encoding="utf-8", newline="\n")
        order_backup = _reorder_material_includes(target_dir)
    elif args.output:
        target_tree.write(args.output, encoding="utf-8", xml_declaration=False, short_empty_elements=True)
    else:
        raise ValueError("Use --output for a preview or --install to update the target tilesets.xml")

    print(json.dumps({
        "installed": args.install,
        "backup": str(backup) if backup else None,
        "materials_order_backup": str(order_backup) if args.install and order_backup else None,
        "tilesets": {name: value for name, value in stats.items() if value["brushes"] or value["items"]},
    }, indent=2))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    summary = subparsers.add_parser("summary", help="summarize DAT/OTB and newly mapped item IDs")
    summary.add_argument("--dat", type=Path, required=True)
    summary.add_argument("--otb", type=Path, required=True)
    summary.add_argument("--old-last-client-id", type=int, required=True)
    summary.add_argument("--output", type=Path)
    summary.set_defaults(func=command_summary)

    generate = subparsers.add_parser(
        "generate",
        help="translate RME material definitions by sprite hash and create semantic tilesets",
    )
    generate.add_argument("--dat", type=Path, required=True)
    generate.add_argument("--target-dir", type=Path, required=True)
    generate.add_argument("--source-dir", type=Path, required=True)
    generate.add_argument("--new-start", type=int, required=True)
    generate.add_argument("--output-dir", type=Path)
    generate.add_argument("--install", action="store_true")
    generate.set_defaults(func=command_generate)

    integrate = subparsers.add_parser(
        "integrate",
        help="merge translated items and brushes into the existing RME palette categories",
    )
    integrate.add_argument("--dat", type=Path, required=True)
    integrate.add_argument("--target-dir", type=Path, required=True)
    integrate.add_argument("--source-dir", type=Path, required=True)
    integrate.add_argument("--new-start", type=int, required=True)
    integrate.add_argument("--output", type=Path)
    integrate.add_argument("--install", action="store_true")
    integrate.set_defaults(func=command_integrate)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
