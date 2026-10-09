# -*- coding: utf-8 -*-
"""
ECDICT 本地查词服务 (只读同目录下的 stardict.db, 不联网)

接口:
    GET /ping            -> "ok" (存活探测)
    GET /lookup?q=单词    -> JSON {found, word, phonetic, meanings, gloss, tags, exchanges}
                            未收录时 {found:false, suggestions:[...]}

启动: pythonw ecdict_server.py   (AHK 脚本会自动拉起, 也可开机自启)
端口: 39777 (127.0.0.1 仅本机可访问)
"""
import json
import os
import sqlite3
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# ================= 配置 =================
# 词库默认与本文件同目录; 若用 PyInstaller 打包成 exe, 则与 exe 同目录
if getattr(sys, "frozen", False):
    APP_DIR = os.path.dirname(os.path.abspath(sys.executable))
else:
    APP_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(APP_DIR, "stardict.db")
PORT = 39777
# ========================================

# 本库字段: translation=中文释义, definition=英文释义, phonetic=英式音标
TAG_MAP = {
    "zk": "中考", "gk": "高考", "cet4": "CET4", "cet6": "CET6",
    "ky": "考研", "toefl": "托福", "ielts": "雅思", "gre": "GRE",
}
EXCH_MAP = {
    "p": "过去式", "d": "过去分词", "i": "现在分词", "3": "三单",
    "r": "比较级", "t": "最高级", "s": "复数",
}
# 查不到时尝试词形还原 (apples->apple, ran->run 这类在词库里有直接条目, 这里兜底)
STEM_RULES = [("ies", "y"), ("ves", "f"), ("es", ""), ("ed", ""), ("ing", ""), ("s", ""), ("d", "")]


def get_conn():
    uri = "file:" + urllib.parse.quote(DB_PATH) + "?mode=ro&immutable=1"
    con = sqlite3.connect(uri, uri=True)
    con.row_factory = sqlite3.Row
    return con


def find_word(cur, w):
    return cur.execute(
        "SELECT * FROM stardict WHERE word = ? COLLATE NOCASE LIMIT 1", (w,)
    ).fetchone()


def lookup(q):
    q = q.strip()
    if not q:
        return {"found": False, "suggestions": []}
    if not os.path.exists(DB_PATH):
        return {"found": False,
                "error": "未找到词库文件 stardict.db (它应与本程序在同一目录)"}

    con = get_conn()
    try:
        cur = con.cursor()
        row = find_word(cur, q)
        if row is None:
            low = q.lower()
            for suf, rep in STEM_RULES:
                if low.endswith(suf) and len(low) > len(suf) + 2:
                    row = find_word(cur, low[: -len(suf)] + rep)
                    if row is not None:
                        break
        if row is None:
            result = {"found": False, "suggestions": []}
            if " " not in q:  # 单词才给联想
                like = q.lower()[: max(2, min(len(q), 4))] + "%"
                rows = cur.execute(
                    "SELECT word FROM stardict WHERE word LIKE ? AND frq > 0 "
                    "ORDER BY frq LIMIT 8", (like,)
                ).fetchall()
                result["suggestions"] = [r[0] for r in rows]
            return result

        tags = [TAG_MAP[t] for t in (row["tag"] or "").split() if t in TAG_MAP]
        meanings = [m.strip() for m in (row["translation"] or "").splitlines() if m.strip()]
        glosses = [m.strip() for m in (row["definition"] or "").splitlines() if m.strip()]
        exchanges = []
        for part in (row["exchange"] or "").split("/"):
            if ":" in part:
                k, v = part.split(":", 1)
                label = EXCH_MAP.get(k)
                if label:
                    exchanges.append(label + ": " + v)

        return {
            "found": True,
            "word": row["word"],
            "phonetic": row["phonetic"] or "",
            "meanings": meanings[:10] or glosses[:3],
            "gloss": " / ".join(glosses[:2]),
            "tags": tags,
            "exchanges": exchanges,
        }
    finally:
        con.close()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):  # 静默访问日志
        pass

    def _send(self, code, body, ctype):
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        try:
            if parsed.path == "/ping":
                self._send(200, "ok", "text/plain; charset=utf-8")
                return
            if parsed.path == "/lookup":
                qs = urllib.parse.parse_qs(parsed.query)
                q = (qs.get("q") or [""])[0]
                self._send(200, json.dumps(lookup(q), ensure_ascii=False),
                           "application/json; charset=utf-8")
                return
            self._send(404, "not found", "text/plain; charset=utf-8")
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            try:
                self._send(500, json.dumps({"found": False, "error": str(e)},
                                           ensure_ascii=False),
                           "application/json; charset=utf-8")
            except Exception:
                pass


def main():
    try:
        srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    except OSError:
        return  # 端口已被占用(多半是服务已在运行)
    srv.daemon_threads = True
    srv.serve_forever()


if __name__ == "__main__":
    main()
