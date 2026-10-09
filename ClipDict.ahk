;=====================================================================
;  剪贴板词典查询 (AutoHotkey v2 + ECDICT 本地词库)
;  用法: 复制单词后快速再按一次 Ctrl+C (即连按两次) -> 鼠标处弹出输入法大小的小窗
;        显示 音标 + 词义; 点击弹窗即关闭, 12 秒无操作自动消失
;        弹窗不抢焦点; 纯本地查询, 不依赖网络
;  依赖: AutoHotkey v2.0+; 词典服务由本脚本自动拉起 —— 同目录的
;        ecdict_server.exe (PyInstaller 打包的独立服务, 无需 Python);
;        服务端口 127.0.0.1:39777
;        词库: 同目录下的 stardict.db (来自 ECDICT 项目)
;=====================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force

CoordMode("Mouse", "Screen")
CoordMode("ToolTip", "Screen")

; ===================== 配置(可自行修改) =====================
DoublePressMs := 400      ; 连按两次 Ctrl+C 触发查词的间隔阈值(毫秒)
AltHotkey     := "^!t"    ; 备用热键 Ctrl+Alt+T; 不需要就改成 ""
AutoCloseSec  := 12       ; 弹窗自动消失的秒数
MaxPopupWidth := 420      ; 弹窗最大宽度(像素)
CardMargin    := 12       ; 卡片四周留白(容纳阴影)
CardRadius    := 10       ; 圆角半径(像素)
DictPort      := 39777    ; 本地词典服务端口
; ============================================================

PopupGui := ""

OnMessage(0x201, PopupLButtonDown)   ; WM_LBUTTONDOWN: 点击弹窗任意处关闭
PopupLButtonDown(wParam, lParam, msg, hwnd) {
    global PopupGui
    if (PopupGui != "" && hwnd = PopupGui.Hwnd) {
        DestroyPopup()
        return 0
    }
}

; 连按两次 Ctrl+C 触发查词 (~ 前缀 = 不拦截按键, 第一次按下仍正常复制)
Hotkey("~^c", OnCopyHotkey)
if (AltHotkey != "")
    Hotkey(AltHotkey, TranslateClipboard)

A_TrayMenu.Add()                                    ; 分隔线
A_TrayMenu.Add("立即查词", TranslateClipboard)
A_TrayMenu.Default := "立即查词"                     ; 双击托盘图标 = 立即查词
A_IconTip := "剪贴板查词  连按两次Ctrl+C" (AltHotkey != "" ? "  或  " PrettyHotkey(AltHotkey) : "")

OnCopyHotkey(*) {
    ; 两次都是同一热键且间隔够短 => 触发查词; 否则保持原生复制行为, 什么都不做
    if (A_ThisHotkey = A_PriorHotkey && A_TimeSincePriorHotkey <= DoublePressMs)
        TranslateClipboard()
}

; ---------------------------- 主流程 ----------------------------

TranslateClipboard(*) {
    text := Trim(A_Clipboard, " `t`r`n")
    if (text = "") {
        FlashTip("剪贴板为空, 请先复制要查询的单词")
        return
    }
    if (StrLen(text) > 120)
        text := SubStr(text, 1, 120)

    EnsureDictService()
    resp := ""
    try resp := HttpGet("http://127.0.0.1:" DictPort "/lookup?q=" UriEncode(text), 5000, true)
    if (resp = "") {
        ShowTipPopup("查询失败", "", "本地词典服务未响应 (端口 " DictPort ")`n请确认脚本同目录存在 ecdict_server.exe 和 stardict.db", false)
        return
    }

    if !RegExMatch(resp, '"found"\s*:\s*true') {
        head := text
        if (StrLen(head) > 90)
            head := SubStr(head, 1, 90) "…"
        err := JsonStr(resp, "error")           ; 服务端报错(如词库缺失)
        if (err != "") {
            ShowTipPopup(head, "", err, false)
            return
        }
        sugg := JsonArrStrings(resp, "suggestions")
        body := "本地词典未收录该词" (sugg.Length > 0 ? "`n您是不是要找:`n" Join("`n", sugg) : "")
        ShowTipPopup(head, "", body, false)
        return
    }

    word  := JsonStr(resp, "word")
    ph    := JsonStr(resp, "phonetic")
    gloss := JsonStr(resp, "gloss")
    means := JsonArrStrings(resp, "meanings")
    tags  := JsonArrStrings(resp, "tags")
    exch  := JsonArrStrings(resp, "exchanges")

    head := (word != "") ? word : text
    phLine := (ph != "") ? "/" ph "/" : ""
    if (tags.Length > 0)
        phLine := phLine ((phLine != "") ? "   " : "") "[" Join("·", tags) "]"

    body := Join("`n", means)
    if (body = "")
        body := gloss
    if (body = "")
        body := "无释义"
    if (exch.Length > 0)
        body .= "`n" Join("   ", exch)

    ShowTipPopup(head, phLine, body, true)
}

; ---------------------- 本地词典服务管理 ----------------------

EnsureDictService() {
    static up := 0, down := 0
    if (up && A_TickCount - up < 60000)
        return
    if (down && A_TickCount - down < 60000)
        return
    if PingDict() {
        up := A_TickCount
        return
    }
    ok := false
    ; 同目录的独立词典服务 (PyInstaller 打包, 目标机器无需装 Python)
    exe := A_ScriptDir "\ecdict_server.exe"
    if FileExist(exe) {
        Run('"' exe '"', A_ScriptDir, "Hide")
        ok := WaitDictUp()
    }
    if (ok)
        up := A_TickCount
    else
        down := A_TickCount                     ; 启动失败, 1 分钟内不重试
}

WaitDictUp() {
    Loop 20 {                       ; 最多等 6 秒(PyInstaller 单文件版首次启动可能较慢)
        Sleep 300
        if PingDict()
            return true
    }
    return false
}

PingDict() {
    try {
        r := HttpGet("http://127.0.0.1:" DictPort "/ping", 1000, true)
        return (r = "ok")
    }
    return false
}

; ---------------------------- HTTP ----------------------------

HttpGet(url, tmo := 8000, direct := false) {
    http := ComObject("WinHttp.WinHttpRequest.5.1")
    if (direct)                     ; 直连不走系统代理(用于本地服务)
        http.SetProxy(1, "", "")
    http.SetTimeouts(2000, 2000, tmo, tmo)
    http.Open("GET", url, false)
    http.SetRequestHeader("User-Agent", "Mozilla/5.0")
    http.Send()
    return BodyToText(http.ResponseBody)
}

BodyToText(v) {
    ; WinHttp 返回字节数组, 统一按 UTF-8 转成文本
    if (ComObjType(v) != 0x2011)
        return ""
    st := ComObject("ADODB.Stream")
    st.Type := 1
    st.Open()
    st.Write(v)
    st.Position := 0
    st.Type := 2
    st.Charset := "UTF-8"
    s := st.ReadText()
    st.Close()
    return s
}

; ------------------------ 编码 / JSON 解析 ------------------------

UriEncode(str) {
    static hex := "0123456789ABCDEF"
    out := ""
    len := StrPut(str, "UTF-8") - 1
    buf := Buffer(len, 0)
    StrPut(str, buf, "UTF-8")
    Loop len {
        b := NumGet(buf, A_Index - 1, "UChar")
        if (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b = 0x2D || b = 0x2E || b = 0x5F || b = 0x7E
            out .= Chr(b)
        else
            out .= "%" SubStr(hex, (b >> 4) + 1, 1) SubStr(hex, (b & 0xF) + 1, 1)
    }
    return out
}

JsonStr(j, key) {
    if RegExMatch(j, '(?s)"' key '"\s*:\s*"((?:\\.|[^"\\])*)"', &m)
        return JsonUnescape(m[1])
    return ""
}

JsonArrStrings(j, key) {
    out := []
    if !RegExMatch(j, '(?s)"' key '"\s*:\s*\[\s*(.*?)\s*\]', &m)
        return out
    inner := m[1]
    p := 1
    while (p := RegExMatch(inner, '"((?:\\.|[^"\\])*)"', &sm, p)) {
        out.Push(JsonUnescape(sm[1]))
        p := p + sm.Len(0)
    }
    return out
}

JsonUnescape(s) {
    out := ""
    i := 1
    n := StrLen(s)
    while (i <= n) {
        c := SubStr(s, i, 1)
        if (c != "\") {
            out .= c
            i += 1
            continue
        }
        e := SubStr(s, i + 1, 1)
        if (e = "u") {
            code := Integer("0x" SubStr(s, i + 2, 4))
            i += 6
            if (code >= 0xD800 && code <= 0xDBFF && SubStr(s, i, 2) = "\u") {
                code2 := Integer("0x" SubStr(s, i + 2, 4))
                if (code2 >= 0xDC00 && code2 <= 0xDFFF) {
                    code := 0x10000 + ((code - 0xD800) << 10) + (code2 - 0xDC00)
                    i += 6
                }
            }
            out .= Chr(code)
        } else if (e = "n") {
            out .= "`n", i += 2
        } else if (e = "t") {
            out .= "`t", i += 2
        } else if (e = "r") {
            out .= "`r", i += 2
        } else if (e = Chr(34)) {
            out .= Chr(34), i += 2
        } else if (e = "\") {
            out .= "\", i += 2
        } else if (e = "/") {
            out .= "/", i += 2
        } else {
            out .= c e, i += 2
        }
    }
    return out
}

Join(sep, arr) {
    s := ""
    for v in arr
        s .= (A_Index > 1 ? sep : "") v
    return s
}

PrettyHotkey(hk) {
    s := hk
    s := StrReplace(s, "^", "Ctrl+")
    s := StrReplace(s, "!", "Alt+")
    s := StrReplace(s, "+", "Shift+")
    s := StrReplace(s, "#", "Win+")
    return s
}

; ---------------------------- 弹窗 UI ----------------------------

ShowTipPopup(head, phonetic, body, ok) {
    global PopupGui
    DestroyPopup()

    GdiplusEnsureStartup()

    ; 文本块: [文本, 字号pt, 是否加粗, 颜色ARGB] — 直接画进分层位图, 不用子控件
    ; (子控件 GDI 文字在分层窗口上 alpha 不对, 会发虚变浅)
    blocks := [[head, 12, true, ok ? 0xFF14161A : 0xFFA8271F]]
    if (phonetic != "")
        blocks.Push([phonetic, 9, false, 0xFF67717E])
    if (body != "")
        blocks.Push([body, 10, false, ok ? 0xFF2B3138 : 0xFF8C3A32])

    fmt := GdiplusDefaultFormat()
    gm := GdiplusMeasureGraphics()
    boxes := []
    contentW := 0, contentH := 0
    gap := 5
    for i, b in blocks {
        box := GdiplusMeasure(gm, b[1], GdipFont(b[2], b[3]), MaxPopupWidth, fmt)
        boxes.Push(box)
        contentW := Max(contentW, box[1])
        contentH += box[2] + (i > 1 ? gap : 0)
    }
    padX := 14, padY := 11
    cardW := Ceil(contentW) + padX * 2
    cardH := Ceil(contentH) + padY * 2
    winW := cardW + CardMargin * 2
    winH := cardH + CardMargin * 2

    g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000 +E0x00080000", "youdao_tip")
    PopupGui := g

    ; 显示在鼠标附近, 并保证不超出屏幕工作区
    MouseGetPos(&mx, &my)
    L := 0, T := 0, R := A_ScreenWidth, B := A_ScreenHeight
    Loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &wl, &wt, &wr, &wb)
        if (mx >= wl && mx <= wr && my >= wt && my <= wb) {
            L := wl, T := wt, R := wr, B := wb
            break
        }
    }
    x := mx + 14, y := my + 22
    if (x + winW > R)
        x := mx - winW - 14
    if (y + winH > B)
        y := my - winH - 22
    x := Max(x, L), y := Max(y, T)
    g.Show("NoActivate x" x " y" y " w" winW " h" winH)

    PaintCardText(g.Hwnd, winW, winH, cardW, cardH, blocks, boxes, padX, padY, ok)

    SetTimer(DestroyPopup, -(AutoCloseSec * 1000))
}

DestroyPopup(*) {
    global PopupGui
    SetTimer(DestroyPopup, 0)
    if (PopupGui != "") {
        try PopupGui.Destroy()
        PopupGui := ""
    }
}

FlashTip(msg) {
    ToolTip(msg)
    SetTimer(() => ToolTip(), -1500)
}

; -------------------- GDI+ 抗锯齿圆角卡片 --------------------

GdiplusEnsureStartup() {
    static token := 0
    if (token != 0)
        return
    si := Buffer(24, 0)
    NumPut("UInt", 1, si, 0)
    DllCall("gdiplus\GdiplusStartup", "ptr*", &token := 0, "ptr", si, "ptr", 0)
}

GdiplusRoundPath(x, y, w, h, r) {
    p := 0
    DllCall("gdiplus\GdipCreatePath", "int", 0, "ptr*", &p := 0)
    d := r * 2
    for , a in [[x, y, 180], [x + w - d, y, 270], [x + w - d, y + h - d, 0], [x, y + h - d, 90]]
        DllCall("gdiplus\GdipAddPathArc", "ptr", p, "float", a[1], "float", a[2]
            , "float", d, "float", d, "float", a[3], "float", 90)
    DllCall("gdiplus\GdipClosePathFigure", "ptr", p)
    return p
}

GdiplusScreenDC() {
    static dc := 0
    if (!dc)
        dc := DllCall("user32\GetDC", "ptr", 0, "ptr")
    return dc
}

GdiplusMeasureGraphics() {
    static g := 0, bmp := 0
    if (g)
        return g
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", 8, "int", 8
        , "int", 0, "int", 0x26200A, "ptr", 0, "ptr*", &bmp := 0)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", bmp, "ptr*", &g := 0)
    return g
}

GdiplusDefaultFormat() {
    static fmt := 0
    if (!fmt)
        DllCall("gdiplus\GdipStringFormatGetGenericDefault", "ptr*", &fmt := 0)
    return fmt
}

GdipFont(pt, bold) {
    static cache := Map()
    key := pt (bold ? "b" : "n")
    if (cache.Has(key))
        return cache[key]
    lf := Buffer(92, 0)                                          ; LOGFONTW
    dpi := A_ScreenDPI > 0 ? A_ScreenDPI : 96
    NumPut("Int", -Round(pt * dpi / 72), lf, 0)                  ; lfHeight (像素)
    NumPut("Int", bold ? 700 : 400, lf, 16)                      ; lfWeight
    NumPut("UChar", 4, lf, 26)                                   ; lfQuality = 抗锯齿
    StrPut("Microsoft YaHei UI", lf.Ptr + 28, 32, "UTF-16")      ; lfFaceName
    font := 0
    DllCall("gdiplus\GdipCreateFontFromLogfontW", "ptr", GdiplusScreenDC(), "ptr", lf, "ptr*", &font := 0)
    cache[key] := font
    return font
}

GdiplusMeasure(g, text, font, maxW, fmt) {
    layout := Buffer(16, 0)
    NumPut("Float", 0, layout, 0), NumPut("Float", 0, layout, 4)
    NumPut("Float", maxW + 1.0, layout, 8), NumPut("Float", 100000.0, layout, 12)
    box := Buffer(16, 0)
    DllCall("gdiplus\GdipMeasureString", "ptr", g, "wstr", text, "int", StrLen(text)
        , "ptr", font, "ptr", layout, "ptr", fmt, "ptr", box, "ptr", 0, "ptr", 0)
    return [NumGet(box, 8, "Float"), NumGet(box, 12, "Float")]
}

PaintCardText(hwnd, w, h, cardW, cardH, blocks, boxes, padX, padY, ok) {
    GdiplusEnsureStartup()
    pBitmap := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", w, "int", h
        , "int", 0, "int", 0x26200A, "ptr", 0, "ptr*", &pBitmap := 0)
    g := 0
    DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", pBitmap, "ptr*", &g := 0)
    DllCall("gdiplus\GdipSetSmoothingMode", "ptr", g, "int", 4)      ; 图形抗锯齿
    DllCall("gdiplus\GdipSetTextRenderingHint", "ptr", g, "int", 4)  ; 文字抗锯齿

    x := CardMargin, y := CardMargin
    cx := x + padX, cy := y + padY
    gap := 5
    fmt := GdiplusDefaultFormat()

    ; 两层半透明描边叠出柔和阴影
    for , sh in [[3, 0x14000000], [1, 0x24000000]] {
        pPath := GdiplusRoundPath(x - sh[1], y - sh[1], cardW + sh[1] * 2, cardH + sh[1] * 2, CardRadius + sh[1])
        brush := 0
        DllCall("gdiplus\GdipCreateSolidFill", "uint", sh[2], "ptr*", &brush := 0)
        DllCall("gdiplus\GdipFillPath", "ptr", g, "ptr", brush, "ptr", pPath)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", brush)
        DllCall("gdiplus\GdipDeletePath", "ptr", pPath)
    }

    ; 卡片底色 + 1px 细边框
    pPath := GdiplusRoundPath(x, y, cardW, cardH, CardRadius)
    brush := 0
    DllCall("gdiplus\GdipCreateSolidFill", "uint", ok ? 0xFFF8F9FB : 0xFFFCF2F1, "ptr*", &brush := 0)
    DllCall("gdiplus\GdipFillPath", "ptr", g, "ptr", brush, "ptr", pPath)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", brush)
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "uint", ok ? 0xFFE4E7EC : 0xFFF0CFCB, "float", 1.0, "int", 2, "ptr*", &pen := 0)
    DllCall("gdiplus\GdipDrawPath", "ptr", g, "ptr", pen, "ptr", pPath)
    DllCall("gdiplus\GdipDeletePen", "ptr", pen)
    DllCall("gdiplus\GdipDeletePath", "ptr", pPath)

    ; 文本(带正确的 alpha, 清晰不发虚)
    for i, b in blocks {
        font := GdipFont(b[2], b[3])
        sbrush := 0
        DllCall("gdiplus\GdipCreateSolidFill", "uint", b[4], "ptr*", &sbrush := 0)
        layout := Buffer(16, 0)
        NumPut("Float", cx, layout, 0), NumPut("Float", cy, layout, 4)
        NumPut("Float", boxes[i][1] + 2, layout, 8), NumPut("Float", boxes[i][2] + 2, layout, 12)
        DllCall("gdiplus\GdipDrawString", "ptr", g, "wstr", b[1], "int", StrLen(b[1])
            , "ptr", font, "ptr", layout, "ptr", fmt, "ptr", sbrush)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", sbrush)
        cy += boxes[i][2] + gap
    }
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", g)

    ; 提交为逐像素透明的分层窗口
    hbm := 0
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "ptr", pBitmap, "ptr*", &hbm := 0, "uint", 0)
    DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)
    hdcMem := DllCall("gdi32\CreateCompatibleDC", "ptr", 0, "ptr")
    obm := DllCall("gdi32\SelectObject", "ptr", hdcMem, "ptr", hbm, "ptr")
    sz := Buffer(8, 0), NumPut("Int", w, sz, 0), NumPut("Int", h, sz, 4)
    ptSrc := Buffer(8, 0)
    blend := Buffer(4, 0)
    NumPut("UChar", 0, blend, 0), NumPut("UChar", 0, blend, 1)     ; AC_SRC_OVER
    NumPut("UChar", 255, blend, 2), NumPut("UChar", 1, blend, 3)   ; 不透明 + 逐像素 alpha
    DllCall("user32\UpdateLayeredWindow", "ptr", hwnd, "ptr", 0, "ptr", 0
        , "ptr", sz, "ptr", hdcMem, "ptr", ptSrc, "uint", 0, "ptr", blend, "uint", 2)
    DllCall("gdi32\SelectObject", "ptr", hdcMem, "ptr", obm)
    DllCall("gdi32\DeleteObject", "ptr", hbm)
    DllCall("gdi32\DeleteDC", "ptr", hdcMem)
}
