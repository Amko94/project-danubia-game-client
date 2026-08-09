"""
Generates modules/game_npctrade/npcshopdata.lua from the sibling game-server's NPC shop scripts.

The server (TFS) uses the classic keyword-based ShopModule (data/npc/lib/npcsystem/modules.lua),
not the binary shop protocol, so item ids/prices only exist in two places:
  1. Inline shopModule:addBuyableItem/addSellableItem/addBuyableItemContainer(...) calls in the
     NPC's .lua script (~66 npcs).
  2. Declarative <parameter key="module_shop" value="1"/> + shop_buyable/shop_sellable parameters
     in the NPC's .xml, auto-registered at runtime by NpcSystem.parseParameters (see
     data/npc/lib/npcsystem/npcsystem.lua:174-184 and modules.lua ShopModule:parseParameters) --
     this is actually the more common style (~222 npcs), and is missed entirely if you only scan
     the .lua scripts.
This script parses both (resolving Cf*-style item id constants via configuration.lua, and falling
back to items.xml for display names) and emits a static Lua table the client module reads at load
time.

Item ids in the npc scripts are *server* ids. The client renders sprites by *client* id, and on
this server the two diverge for the majority of items (items.otb stores both per item -- see
ITEM_ATTR_SERVERID/ITEM_ATTR_CLIENTID in game-server/src/itemloader.h). We parse items.otb (a
node-tree binary format, see game-server/src/fileloader.cpp for the framing) to translate every
server id to the client id actually used by Item.create() in the dialog.

Re-run whenever server-side NPC shops or items.otb change:
    py tools/generate_npcshopdata.py
"""
import os
import re
import struct
import xml.etree.ElementTree as ET

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CLIENT_ROOT = os.path.dirname(SCRIPT_DIR)
SERVER_ROOT = os.path.normpath(os.path.join(CLIENT_ROOT, "..", "game-server"))
NPC_DIR = os.path.join(SERVER_ROOT, "data", "npc")
SCRIPTS_DIR = os.path.join(NPC_DIR, "scripts")
CONFIG_LUA = os.path.join(NPC_DIR, "lib", "configuration.lua")
ITEMS_XML = os.path.join(SERVER_ROOT, "data", "items", "items.xml")
ITEMS_OTB = os.path.join(SERVER_ROOT, "data", "items", "items.otb")
OUTPUT_LUA = os.path.join(CLIENT_ROOT, "modules", "game_npctrade", "npcshopdata.lua")

OTB_NODE_START = 0xFE
OTB_NODE_END = 0xFF
OTB_ESCAPE = 0xFD
OTB_ITEM_ATTR_SERVERID = 0x10
OTB_ITEM_ATTR_CLIENTID = 0x11

CONST_LINE = re.compile(r"^([A-Za-z_]\w*)\s*=\s*(-?\d+)\s*$")
SHOP_CALL = re.compile(
    r"shopModule:add(Buyable|Sellable)Item(Container)?\s*\("
)


def load_constants(path):
    constants = {}
    with open(path, encoding="utf-8", errors="ignore") as f:
        for line in f:
            m = CONST_LINE.match(line.strip())
            if m:
                constants[m.group(1)] = int(m.group(2))
    return constants


def load_item_names(path):
    names = {}
    tree = ET.parse(path)
    for item in tree.getroot().findall("item"):
        item_id = item.get("id")
        name = item.get("name")
        if item_id and name:
            names[int(item_id)] = name
        from_id, to_id = item.get("fromid"), item.get("toid")
        if from_id and to_id and name:
            for i in range(int(from_id), int(to_id) + 1):
                names[i] = name
    return names


def _parse_otb_node(data, pos):
    assert data[pos] == OTB_NODE_START
    pos += 1
    node_type = data[pos]
    pos += 1
    props = bytearray()
    children = []
    while True:
        b = data[pos]
        if b == OTB_NODE_START:
            child, pos = _parse_otb_node(data, pos)
            children.append(child)
        elif b == OTB_NODE_END:
            pos += 1
            break
        elif b == OTB_ESCAPE:
            props.append(data[pos + 1])
            pos += 2
        else:
            props.append(b)
            pos += 1
    return {"type": node_type, "props": bytes(props), "children": children}, pos


def load_client_ids(path):
    """Maps server item id -> client item id, parsed from items.otb (see
    game-server/src/fileloader.cpp for the node-tree framing and
    game-server/src/items.cpp Items::loadFromOtb for the attribute layout)."""
    with open(path, "rb") as f:
        data = f.read()

    root, _ = _parse_otb_node(data, 4)  # first 4 bytes are a file identifier, root node starts at 4

    client_ids = {}
    for item_node in root["children"]:
        props = item_node["props"]
        offset = 4  # skip the 4-byte flags field
        server_id = None
        client_id = None
        while offset < len(props):
            attrib = props[offset]
            offset += 1
            datalen = struct.unpack_from("<H", props, offset)[0]
            offset += 2
            value = props[offset:offset + datalen]
            if attrib == OTB_ITEM_ATTR_SERVERID and datalen == 2:
                server_id = struct.unpack("<H", value)[0]
                if 30000 < server_id < 30100:
                    server_id -= 30000
            elif attrib == OTB_ITEM_ATTR_CLIENTID and datalen == 2:
                client_id = struct.unpack("<H", value)[0]
            offset += datalen
        if server_id is not None and client_id is not None:
            client_ids[server_id] = client_id
    return client_ids


def split_top_level_args(argstr):
    """Split a Lua call's argument string on top-level commas, respecting {}, (), and quotes."""
    args = []
    depth = 0
    quote = None
    current = []
    i = 0
    while i < len(argstr):
        ch = argstr[i]
        if quote:
            current.append(ch)
            if ch == quote and argstr[i - 1] != "\\":
                quote = None
        elif ch in "'\"":
            quote = ch
            current.append(ch)
        elif ch in "{(":
            depth += 1
            current.append(ch)
        elif ch in ")}":
            depth -= 1
            current.append(ch)
        elif ch == "," and depth == 0:
            args.append("".join(current).strip())
            current = []
        else:
            current.append(ch)
        i += 1
    if current:
        args.append("".join(current).strip())
    return args


def parse_names_table(arg):
    """Parse a Lua table literal of quoted strings, e.g. {'a', 'b'} -> ['a', 'b']."""
    inner = arg.strip()
    if inner.startswith("{"):
        inner = inner[1:]
    if inner.endswith("}"):
        inner = inner[:-1]
    names = []
    for piece in split_top_level_args(inner):
        piece = piece.strip()
        m = re.match(r"^(['\"])(.*)\1$", piece, re.DOTALL)
        if m:
            names.append(m.group(2))
    return names


def resolve_id(arg, constants):
    arg = arg.strip()
    if re.match(r"^-?\d+$", arg):
        return int(arg)
    return constants.get(arg)


def parse_number(arg):
    arg = arg.strip()
    if re.match(r"^-?\d+$", arg):
        return int(arg)
    return None


def parse_string_literal(arg):
    arg = arg.strip()
    m = re.match(r"^(['\"])(.*)\1$", arg, re.DOTALL)
    return m.group(2) if m else None


def find_matching_paren(text, open_idx):
    depth = 0
    i = open_idx
    while i < len(text):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def parse_shop_script(path, constants, item_names, client_ids, skips):
    with open(path, encoding="utf-8", errors="ignore") as f:
        text = f.read()

    buy, sell = [], []

    for m in SHOP_CALL.finditer(text):
        kind = m.group(1)  # Buyable / Sellable
        is_container = bool(m.group(2))
        open_paren = m.end() - 1
        close_paren = find_matching_paren(text, open_paren)
        if close_paren == -1:
            skips.append(f"{path}: unbalanced parens near offset {m.start()}")
            continue
        argstr = text[open_paren + 1:close_paren]
        args = split_top_level_args(argstr)
        line_no = text.count("\n", 0, m.start()) + 1

        try:
            if is_container:
                # addBuyableItemContainer(names, container, itemid, cost, subType?, realName?)
                if len(args) < 4:
                    raise ValueError("too few args")
                names = parse_names_table(args[0])
                # use the container's own id for display (it's what actually lands in the inventory)
                item_id = resolve_id(args[1], constants)
                cost = parse_number(args[3])
                real_name = parse_string_literal(args[5]) if len(args) > 5 else None
            elif kind == "Buyable":
                # addBuyableItem(names, itemid, cost, itemSubType?, realName?)
                if len(args) < 3:
                    raise ValueError("too few args")
                names = parse_names_table(args[0])
                item_id = resolve_id(args[1], constants)
                cost = parse_number(args[2])
                real_name = parse_string_literal(args[4]) if len(args) > 4 else None
                if real_name is None and len(args) > 3:
                    # some scripts pass the display name in the subType slot by mistake
                    real_name = parse_string_literal(args[3])
            else:
                # addSellableItem(names, itemid, cost, realName?, itemSubType?)
                if len(args) < 3:
                    raise ValueError("too few args")
                names = parse_names_table(args[0])
                item_id = resolve_id(args[1], constants)
                cost = parse_number(args[2])
                real_name = parse_string_literal(args[3]) if len(args) > 3 else None

            if item_id is None or cost is None or not names:
                raise ValueError(f"unresolved item_id/cost/names ({args})")

            entry = make_entry(item_id, cost, names[0], real_name, item_names, client_ids, skips, f"{path}:{line_no}")
            if kind == "Buyable":
                buy.append(entry)
            else:
                sell.append(entry)
        except ValueError as e:
            skips.append(f"{path}:{line_no}: {e} -- {m.group(0)}(...)")

    return buy, sell


def make_entry(item_id, cost, keyword, real_name, item_names, client_ids, skips, context):
    display_name = real_name or item_names.get(item_id) or keyword
    client_id = client_ids.get(item_id)
    if client_id is None:
        skips.append(f"{context}: no client id for server id {item_id} in items.otb, falling back to server id")
        client_id = item_id
    return {"id": item_id, "clientId": client_id, "name": display_name, "keyword": keyword, "price": cost}


def parse_xml_shop_list(value, item_names, client_ids, skips, context):
    """Parses a shop_buyable/shop_sellable npc <parameter> value: a ';'-separated list of
    'name,itemid,cost[,subType[,realName]]' entries (see ShopModule:parseBuyable/parseSellable
    in game-server/data/npc/lib/npcsystem/modules.lua)."""
    entries = []
    for chunk in value.split(";"):
        chunk = chunk.strip()
        if not chunk:
            continue
        fields = [f.strip() for f in chunk.split(",")]
        if len(fields) < 3:
            skips.append(f"{context}: malformed shop entry '{chunk}'")
            continue
        name = fields[0]
        try:
            item_id = int(fields[1])
            cost = int(fields[2])
        except ValueError:
            skips.append(f"{context}: non-numeric id/cost in '{chunk}'")
            continue
        real_name = fields[4] if len(fields) > 4 and fields[4] else None
        entries.append(make_entry(item_id, cost, name, real_name, item_names, client_ids, skips, f"{context} '{chunk}'"))
    return entries


def lua_string(s):
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"


def emit_lua(npc_shops):
    lines = ["NpcShopData = {"]
    for npc_name in sorted(npc_shops.keys()):
        buy, sell = npc_shops[npc_name]
        lines.append(f"  [{lua_string(npc_name)}] = {{")
        for label, items in (("buy", buy), ("sell", sell)):
            if not items:
                lines.append(f"    {label} = {{}},")
                continue
            lines.append(f"    {label} = {{")
            for item in items:
                lines.append(
                    "      { id = %d, clientId = %d, name = %s, keyword = %s, price = %d },"
                    % (item["id"], item["clientId"], lua_string(item["name"]), lua_string(item["keyword"]), item["price"])
                )
            lines.append("    },")
        lines.append("  },")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    constants = load_constants(CONFIG_LUA)
    item_names = load_item_names(ITEMS_XML)
    client_ids = load_client_ids(ITEMS_OTB)

    npc_shops = {}  # npc_name -> (buy list, sell list), deduped by (id, keyword, price)
    seen_keys = {}  # npc_name -> set of (buy/sell, id, keyword, price) already added
    skips = []

    def add_entries(npc_name, buy, sell):
        if not buy and not sell:
            return
        dst_buy, dst_sell = npc_shops.setdefault(npc_name, ([], []))
        seen = seen_keys.setdefault(npc_name, set())
        for label, src, dst in (("buy", buy, dst_buy), ("sell", sell, dst_sell)):
            for entry in src:
                key = (label, entry["id"], entry["keyword"], entry["price"])
                if key in seen:
                    continue
                seen.add(key)
                dst.append(entry)

    for xml_name in os.listdir(NPC_DIR):
        if not xml_name.endswith(".xml"):
            continue
        xml_path = os.path.join(NPC_DIR, xml_name)
        try:
            root = ET.parse(xml_path).getroot()
        except ET.ParseError:
            continue
        npc_name = root.get("name")
        script = root.get("script")
        if not npc_name:
            continue

        # 1. declarative shop via <parameter key="module_shop"> + shop_buyable/shop_sellable,
        #    auto-registered at runtime by NpcSystem.parseParameters (npcsystem.lua:174-184)
        params = {}
        parameters_node = root.find("parameters")
        if parameters_node is not None:
            for p in parameters_node.findall("parameter"):
                key = p.get("key")
                if key:
                    params[key] = p.get("value")

        module_shop = params.get("module_shop")
        if module_shop is not None and module_shop != "0":
            context = f"{xml_path}"
            xml_buy = parse_xml_shop_list(params.get("shop_buyable") or "", item_names, client_ids, skips, context)
            xml_sell = parse_xml_shop_list(params.get("shop_sellable") or "", item_names, client_ids, skips, context)
            add_entries(npc_name, xml_buy, xml_sell)

        # 2. inline shopModule:add(Buyable|Sellable)Item(Container)?(...) calls in the .lua script
        if script and "/" not in script and "\\" not in script:
            script_path = os.path.join(SCRIPTS_DIR, script)
            if os.path.isfile(script_path):
                with open(script_path, encoding="utf-8", errors="ignore") as f:
                    script_text = f.read()
                if "shopModule:add" in script_text:
                    script_buy, script_sell = parse_shop_script(script_path, constants, item_names, client_ids, skips)
                    add_entries(npc_name, script_buy, script_sell)

    total_buy = sum(len(buy) for buy, _ in npc_shops.values())
    total_sell = sum(len(sell) for _, sell in npc_shops.values())

    with open(OUTPUT_LUA, "w", encoding="utf-8") as f:
        f.write(emit_lua(npc_shops))

    print(f"Generated {OUTPUT_LUA}")
    print(f"NPCs with shops: {len(npc_shops)}, buy entries: {total_buy}, sell entries: {total_sell}")
    if skips:
        print(f"\nSkipped {len(skips)} unparsed line(s):")
        for s in skips:
            print(f"  {s}")


if __name__ == "__main__":
    main()
