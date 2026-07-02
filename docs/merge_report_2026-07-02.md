# マージ作業レポート & ティアリング対策ロードマップ（2026-07-02）

対象: `main` ブランチへの強制マージ後の復旧作業
作成者: Claude Code（tatsubon0107 の指示のもと作業）
ステータス: **コンパイルが通る状態まで復旧済み。まだ実機コンパイル未確認・未コミット。**

---

## 1. 経緯

相方の作業中ブランチ（ティアリング対策の実装、`deca7c1` 由来）を `main` に強制マージした結果、
以下のファイルで構文エラー・重複宣言・誤ったポート接続が発生し、そのままではコンパイルが通らない状態になっていました。

このレポートは「まず動く状態に戻すこと」を優先して行った応急修正の内容をまとめたものです。
**設計そのものを見直したわけではない**ので、次回作業時にどこを引き継ぐべきかも合わせて記載します。

変更したファイル（`git status` で確認済み、他のファイルへの影響なし）:

- `src/difference/difference_calc.v`
- `src/difference/difference.v`
- `src/adv7513/PVI.v`
- `src/adv7513/adv7513.v`
- `src/TopModule.v`

---

## 2. 修正した問題一覧

| ファイル | 問題 | 対応 |
|---|---|---|
| `difference_calc.v` | `input wire mode2;` が2重宣言 | 1つに整理 |
| `difference_calc.v` | `framedone` が `output reg framedone`（ポート宣言）と `reg framedone;`（内部宣言）の2重宣言 | 内部の `reg framedone;` を削除（ポート宣言側の `reg` で足りる） |
| `difference.v` | `input wire mode2;` が2重宣言 | 1つに整理 |
| `PVI.v` | ポートリスト末尾に余分なカンマ（`output frame_done,\n);`）で構文エラー | カンマを削除 |
| `PVI.v` | `phase` レジスタが未宣言の `framedone` を参照（存在しない識別子） | ブロックごと削除。この `phase` は元々どこからも使われておらず、実際の読み出し側バッファ切替は `display_phase`（入力ポート）のみで完結していた重複ロジックだった |
| `adv7513.v` | `PVI` のインスタンス化で `.frame_done(frame_done)` が2箇所重複 | 1つに整理 |
| `adv7513.v` | `switchR` / `switchG` / `switchB` が `PVI` のインスタンス化で接続されているが、`PVI.v` 側にそのポートが存在せず、`adv7513.v` 側でも未宣言の識別子 | 接続を削除（このスイッチ群は以前のセッションで「実際には一切使われていない」と確認済みで `TopModule.v` / `PVI.v` / `README.md` から撤去済みだった。相方ブランチのマージで復活していたので再撤去） |
| `TopModule.v` | `frame_difference` のインスタンス化で `.mode` / `.mode2` が2重接続 | 1つに整理 |
| `TopModule.v` | `frame_difference` のインスタンス化が存在しない `.center_x` / `.center_y` ポートに接続（相方の別ブランチの旧インターフェース名の残骸） | 現行のポート名 `.count` / `.sum_x` / `.sum_y`（しきい値超過画素数・座標総和の生値）に接続し直した |
| `TopModule.v` | `write_phase` が `display_phase`（clock25 ドメイン）を CAM_PCLK ドメインで直接参照しており CDC 未対策 | すぐ下に用意されていた2段同期レジスタ `display_phase_cam_d2` を使うよう修正（レジスタ自体はマージ前から存在していたが未使用だった） |
| `TopModule.v` | `motion_cdc`（`u_motion_cdc`）のインスタンス化が完全に2重 | 2つ目のブロックを削除（同一インスタンス名 + 同一出力ワイヤの2重駆動という致命的エラーだった） |
| `TopModule.v` | `soc_system`（`u_soc_system`）のインスタンス化が完全に2重 | 2つ目のブロックを削除（同一インスタンス名 + HPS 物理ピンの2重駆動という致命的エラーだった） |

各修正箇所には `★マージ整理` というコメントを付与し、どのようにコンフリクトを吸収したかをコード中に明記してあります。

---

## 3. 意図的に踏襲した相方側の設計変更

- **`f_dist` のトグル廃止 → `framedone` パルス方式**: `difference_calc.v` で `f_dist <= ~f_dist;` がコメントアウトされ、代わりに1フレーム完了ごとに1サイクルだけ立つ `framedone` パルスに置き換えられていました。これは相方の意図的な変更と判断し、そのまま尊重しています。
  - 副作用として `TopModule.v` 側で HPS 通知用に使っていた「`f_dist` のトグルエッジ検出」ロジック（`f_dist_d` / `f_dist_edge`）が機能しなくなっていたため、`framedone` を直接使う形に書き換えました（`motion_frame_done = framedone && (motion_count > MOTION_COUNT_THRESHOLD)`）。

## 4. 今回やっていないこと（引き継ぎ事項）

- **ティアリング対策そのものの完成度**: 今回の修正はあくまで「コンパイルが通り、既存の配線が矛盾なく繋がる」状態への復旧です。ダブルバッファの読み書きタイミングの根本的な同期はまだ不十分です（詳細は次章）。
- 実機コンパイル・書き込みでの動作確認は未実施（これから行う想定）。
- RTL シミュレーションは未実施。
- HPS 側ソフトウェア（`motion_test.c` 等）への変更なし。
- `git commit` はまだしていません（必要であれば別途指示してください）。

---

## 5. ティアリング解消ロードマップ

### 5.1 現状の仕組み（おさらい）

BRAM (`bram_2port`) を QVGA 1フレーム分（320×240 = 76,800）×2バンクのダブルバッファとして使っている。

- **書き込み側**（CAM_PCLK ドメイン、`frame_difference` → `difference_calc.v`）
  - `write_phase` が 1 の間はアドレスに `BASE(=76800)` を足してバンク1へ、0 の間はバンク0へ書き込む。
  - `write_phase = ~display_phase_cam_d2`（`display_phase` を2段FFで CAM_PCLK ドメインに同期化した信号の反転）。
  - `current_addr_d2 == 76799` に到達した時点でそのフレームの `count/sum_x/sum_y` を確定し、`framedone` を1サイクル立てる。
- **読み出し側**（clock25 ドメイン、`adv7513.v` + `PVI.v`）
  - `display_phase` が 1 ならバンク1、0 ならバンク0を読む。
  - `display_phase` は **VGA走査が1フレーム終わるたび**（`PVI.v` の `frame_done`、`pixelH`/`pixelV` がそれぞれの `TOTAL-1` に達した時）に無条件でトグルする。

### 5.2 現状のギャップ（なぜティアリングが起きうるか）

問題は **読み出し側 (`display_phase`) の切り替えタイミングが、書き込み側の「新しいフレームが完成したかどうか」と一切連動していない**ことです。

- `display_phase` は 60Hz の VGA 走査完了のたびに機械的にトグルする。
- 一方カメラ側の1フレーム書き込み完了（`framedone`）は、カメラのフレームレートに依存し、必ずしも 60Hz と同期していない（多くの場合もっと遅い）。
- そのため、書き込み側がまだバンク X への書き込みを完了していない途中で、読み出し側が「もう次の VGA フレームだから」という理由だけでバンク X の読み出しに切り替わってしまうケースがあり得ます。これが古い絵と新しい絵が混ざって表示される＝ティアリングの直接原因です。

`write_phase` 側（書き込み先バンクの選択）は「今表示中でないバンクに書く」という設計なので CDC さえ正しければ理屈上は安全ですが、`display_phase` 側（表示バンクの選択）が「書き込み完了」を一切見ていない片手落ちの設計になっている、というのが根本原因です。

### 5.3 解決の方向性

読み出し側が **「新しいフレームが完成した」という事実を、書き込み側から明示的に受け取ってから** バンクを切り替えるようにします。つまり、今すでにある `motion_cdc.v` と同じ「トグルビット + 2段FF同期 + エッジ検出」というパルスの CDC パターンを、`framedone`（CAM_PCLK ドメイン）→ clock25 ドメイン向けにもう1系統作ります。

```
[CAM_PCLK ドメイン]                          [clock25 ドメイン]
frame_difference.framedone (1cycle pulse)
        │
        ▼
  req_toggle (反転)  ──2段FF同期──▶  sync1 / sync1_d ──エッジ検出──▶ frame_ready_pulse（1cycle, clock25）
                                                                          │
                                                                          ▼
                                                            frame_ready_flag（sticky, セット）
```

そして `adv7513.v` の `display_phase` トグル条件を、現在の

```verilog
end else if (frame_done) begin
    display_phase <= ~display_phase;
end
```

から、「VGA走査が1フレーム終わった」かつ「前回スワップ以降に新しいフレームが書き終わっている」の **AND 条件** に変更します。

```verilog
end else if (frame_done && frame_ready_flag) begin
    display_phase   <= ~display_phase;
    frame_ready_flag <= 1'b0;  // 消費したのでクリア
end
```

これにより、カメラ側の書き込みが VGA の走査速度より遅い場合は同じバンクを複数 VGA フレーム分表示し続けるだけになり（＝新しい絵がまだ来ていないなら古い絵をそのまま出す、これは正常動作）、逆に書き込みがまだ終わっていないバンクに読み出しが踏み込むことはなくなります。

### 5.4 実装ステップ（タスク分解）

1. **新規モジュール `src/hps_if/motion_cdc.v` と同じパターンで `src/adv7513/frame_ready_cdc.v`（仮称）を新規作成**
   - 入力: `clock_src(CAM_PCLK)`, `reset_src`, `frame_done_src`（= `framedone`）
   - 出力: `clock_dst(clock25)`, `reset_dst`, `frame_ready_pulse_dst`（1サイクルパルス）
   - 中身は `motion_cdc.v` の `motion_frame_done_src` → `new_data_pulse_dst` の部分だけを抜き出したもの、と考えれば流用しやすいはずです。
2. **`adv7513.v` に `frame_ready_flag`（sticky レジスタ）を追加**
   - `frame_ready_pulse_dst` が立ったらセット、`display_phase` をトグルしたらクリア。
   - `display_phase` のトグル条件を `frame_done && frame_ready_flag` に変更（5.3節参照）。
3. **`TopModule.v` に `frame_ready_cdc` をインスタンス化**
   - `frame_done_src` に `framedone`（CAM_PCLK ドメイン、既存ワイヤ）を接続。
   - `frame_ready_pulse_dst` を `adv7513` の新規入力ポートとして渡す。
4. **`write_phase` 側は現状のままでよい**（今回すでに正しい CDC 方向〈`display_phase_cam_d2`〉に修正済みなので、書き込み側の安全性は担保されています）。

### 5.5 検証方法

- **RTL シミュレーション（推奨・最優先）**: `frame_done_src` をカメラフレームレート相当の間隔で、`frame_done`（VGA側）を 60Hz 相当で独立に駆動するテストベンチを作り、`display_phase` が「書き込み未完了のバンク」に切り替わらないことを波形で確認する。`motion_cdc.v` 用に同種のテストベンチがあれば流用できます。
- **実機確認**: カメラの前で速い動きを作り、HDMI 出力画面に横方向の裂け目（ティアリング特有の症状）が出ないか目視確認。特に、意図的にカメラのフレームレートを落とす/上げる条件（照明を暗くする等）でも症状が出ないか確認すると設計の妥当性を検証しやすいです。
- **タイミング解析**: 新規追加する2段同期FF（`sync1`/`sync1_d`相当）は `motion_cdc.v` の既存同期回路と同じ扱いで、TimeQuest 上は false path 相当になる想定です。`.sdc` の変更が必要になった場合は Quartus の SDC エディタ経由での対応を案内してください（`CLAUDE.md` の運用ルールにより `.sdc` の直接編集はしない）。

### 5.6 補足: 今回は着手しない理由

このダブルバッファ機構自体は相方が着手中の設計であり、今回のセッションの目的は「マージ後にコンパイルが通る状態に戻すこと」に限定されています。5.3〜5.5 の設計変更は相方が実装を再開する際の指針として提示するもので、今回のコード修正には含めていません。
