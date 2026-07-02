# OV7670 → BRAM → HDMI グレースケールカメラ表示

OV7670 カメラから QVGA (320×240) グレースケール映像を取り込み、BRAM を経由して
VGA 640×480 @ 60Hz で HDMI モニタに出力する Cyclone V / DE10-Nano 向けプロジェクトです。

---

## システム構成

```
OV7670 (YUV422 / QVGA 320×240, ~5 MHz PCLK)
        │  capture_gray — Y成分のみ抽出 (YUV422 → 8bit グレー)
        │  Port A (CAM_PCLK, 書き込み)
        ▼
  ┌─────────────┐
  │ BRAM 2-Port │  8bit × 307200 words  (有効: 76,800 words = 320×240)
  └─────────────┘
        │  Port B (clock25 = 25.175 MHz, 読み出し)
        ▼
    PVI.v (ピクセルカウンタ + 2×2 アップスケール)
        │  QVGA pixel → 2×2 VGA block (640×480 @ 60Hz)
        ▼
  ADV7513 → HDMI 出力 (640×480 @ 60Hz)
```

---

## モジュール階層

```
TopModule
├── pll_25          — 50 MHz → 25.175 MHz (VGA ピクセルクロック)   [Quartus IP]
├── pll_5           — 50 MHz → 25 MHz     (OV7670 XCLK)            [Quartus IP]
├── camera          — OV7670 カメラサブシステム
│   ├── capture_gray        — PCLK ドメイン YUV422→Y キャプチャ → BRAM Port A
│   └── sccb/
│       ├── ov7670_init     — SCCB 初期化シーケンサ (レジスタ 23 エントリ)
│       └── ov7670_sccb_write — 100 kHz SCCB ライタ
├── bram_2port      — デュアルポート RAM 8bit × 307200              [Quartus IP]
│     Port A: 書き込み ← camera/capture_gray  (CAM_PCLK ドメイン)
│     Port B: 読み出し → adv7513/PVI          (clock25 ドメイン)
└── adv7513         — HDMI 出力ブロック
    ├── PVI.v               — VGA タイミング生成 + 2× アップスケール
    └── I2C_HDMI_Config.v   — ADV7513 I2C 初期設定
```

---

## 開発環境

| 項目 | 値 |
|------|-----|
| ツール | Quartus Prime Standard Edition 25.1 |
| ターゲット | Intel Cyclone V (DE10-Nano) |
| 言語 | Verilog-2001 |

---

## BRAM 仕様

| 項目 | 値 |
|------|-----|
| データ幅 | 8 ビット（グレースケール: 0x00=黒, 0xFF=白） |
| 深さ（IP 設定値） | 307,200 words (640×480) |
| カメラ有効使用域 | 76,800 words (320×240) — アドレス 0 〜 76,799 |
| アドレス幅 | 19 ビット `[18:0]` |
| Port A クロック | CAM_PCLK（OV7670 出力、約 5 MHz） |
| Port B クロック | clock25（25.175 MHz） |
| 出力モード | UNREGISTERED（両ポート） |

### アドレスマッピング（QVGA 領域）

```
addr = V × 320 + H     (H: 0..319, V: 0..239)
     = (V << 8) + (V << 6) + H   // 乗算なし実装
```

| 座標 | アドレス |
|------|---------|
| (0, 0)     — 左上     | 0x00000 (0)      |
| (319, 0)   — 右上     | 0x0013F (319)    |
| (319, 239) — 右下     | 0x12BFF (76,799) |

---

## OV7670 SCCB 初期化レジスタ

`ov7670_init.v` が電源投入時に順次書き込むレジスタ一覧です（100 kHz SCCB、clock50 動作）。

| インデックス | アドレス | データ | 説明 |
|---|---|---|---|
| 0  | 0x12 | 0x80 | COM7: ソフトウェアリセット |
| 1  | —    | —    | **10 ms ウェイト**（内部リセット完了待ち） |
| 2  | 0x09 | 0x00 | COM2: 出力ドライブ強度 1x |
| 3  | 0x11 | 0x01 | CLKRC: 内部クロック 2 分周 |
| 4  | 0x12 | 0x10 | COM7: QVGA(bit4=1) + YUV 出力 |
| 5  | 0x0C | 0x04 | COM3: DCW（デシメーション）有効 |
| 6  | 0x3E | 0x19 | COM14: PCLK 2 分周 |
| 7  | 0x70 | 0x3A | SCALING_XSC: 水平スケーリング係数 |
| 8  | 0x71 | 0x35 | SCALING_YSC: 垂直スケーリング係数 |
| 9  | 0x72 | 0x11 | SCALING_DCWCTR: 水平 2x + 垂直 2x 間引き |
| 10 | 0x73 | 0xF1 | SCALING_PCLK_DIV: COM14 と連動して 2 分周 |
| 11 | 0xA2 | 0x02 | SCALING_PCLK_DELAY: スケーリング後遅延補正 |
| 12 | 0x17 | 0x16 | HSTART: 水平開始位置 |
| 13 | 0x18 | 0x04 | HSTOP: 水平終了位置 |
| 14 | 0x32 | 0x80 | HREF: 水平タイミング補正 |
| 15 | 0x19 | 0x02 | VSTART: 垂直開始位置 |
| 16 | 0x1A | 0x7A | VSTOP: 垂直終了位置 |
| 17 | 0x03 | 0x0A | VREF: 垂直タイミング補正 |
| 18 | 0x40 | 0xC0 | COM15: 出力レンジ全域 [0–255] |
| 19 | 0x3A | 0x04 | TSLB: YUYV バイト順（Y0, Cb, Y1, Cr） |
| 20 | 0x14 | 0x08 | COM9: AGC/AEC ゲイン上限 2x |
| 21 | 0x8C | 0x00 | RGB444: 無効 |
| 22 | 0x6B | 0x4A | DBLV: 内部 PLL 4 倍（10 MHz × 4 = 40 MHz） |

---

## トップレベルポート一覧

| 信号名 | 方向 | 説明 |
|--------|------|------|
| `clock50` | input | 50 MHz システムクロック |
| `reset_n` | input | アクティブ Low リセット |
| `HDMI_TX_D[23:0]` | output | HDMI RGB データ |
| `HDMI_TX_VS/HS/DE` | output | HDMI 同期信号 |
| `HDMI_TX_CLK` | output | HDMI ピクセルクロック |
| `HDMI_TX_INT` | input | ADV7513 割り込み |
| `HDMI_I2C_SDA/SCL` | inout/output | ADV7513 I2C |
| `READY` | output | ADV7513 設定完了 |
| `locked` | output | PLL ロック状態 |
| `CAM_PCLK` | input | OV7670 ピクセルクロック |
| `CAM_VSYNC` | input | OV7670 垂直同期 |
| `CAM_HREF` | input | OV7670 水平有効期間 |
| `CAM_D[7:0]` | input | OV7670 8bit データバス |
| `CAM_XCLK` | output | OV7670 入力クロック（25 MHz） |
| `CAM_SIOD` | inout | SCCB データ |
| `CAM_SIOC` | output | SCCB クロック |
| `CAM_RESET` | output | OV7670 リセット（通常 High） |
| `CAM_PWDN` | output | OV7670 パワーダウン（通常 Low） |
| `CAM_INIT_DONE` | output | SCCB 初期化完了インジケータ（LED 用） |
| `CAM_PCLK_ACT` | output | PCLK 受信中インジケータ（LED 用） |

---

## 注意事項

- 映像が出ない場合は `CAM_INIT_DONE` と `CAM_PCLK_ACT` の LED で状態を確認してください。
- `CAM_INIT_DONE` が立ち上がるまで BRAM への書き込みはゲートされます。
- Port A・Port B が同一アドレスへ同時アクセスした場合、書き込みデータが読み出されます
  (`NEW_DATA_NO_NBE_READ`)。一瞬ちらつく可能性はありますが映像は壊れません。
- カメラ出力は **QVGA 320×240 グレースケール**固定です。PVI が 2×2 ブロックで拡大し
  HDMI は常に 640×480 で出力します。

---

## Credits

Based on [de10nano_vgaHdmi_chip](https://github.com/nhasbun/de10nano_vgaHdmi_chip) by Nicolas Hasbun, licensed under the MIT License.
