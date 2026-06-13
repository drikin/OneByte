# OneByte

**2バイト言語で生きる僕たちのためのIME。**

日本語をローマ字入力するすべての人が知っているあの苦労——KotoeriやGoogle日本語入力に切り替えて、ローマ字を打ち、スペースを十数回叩いて変換候補を巡回し、文節区切りが間違ってることに気づいてBackspace、区切り直してまた変換、そしてURLをコピーしようとして英数モードに切り替えるのを忘れて大文字が連打される… もう十分でしょう。

OneByteは50年前から変わらないIMEのパラダイムをぶち壊します。

**ローマ字を打つ。Enterを押す。日本語が出る。**

打ち間違い？ 抜け文字？ 文節区切りが適当？ 全部LLMが一発で直します。変換候補ウィンドウも、モード切り替えも、スペース連打も必要ありません。

英語が欲しいなら **Shift+Enter。** 一発英訳。

Swift + InputMethodKit で構築。バックエンドはローカルLLM（DGX Spark クラスタ上の vLLM）。

## 使い方

```
watashi wa kyou gakkou ni ikimashita
         ↓ Enter
私は今日学校に行きました。
```

```
koreha tesuto desu
         ↓ Shift+Enter
This is a test.
```

## キーバインド

| キー | 動作 |
|---|---|
| ローマ字を打つ | 下線付きマークテキストに蓄積 |
| **Space** | 文節区切り |
| **Enter** | 全文を日本語に変換・確定 |
| **Shift+Enter** | 日本語にしてから英訳・確定 |
| **Tab** | ローマ字のまま確定（LLMを通さない） |
| **Backspace** | 1文字削除 / 前の文節に戻る |
| **Escape** | 全文クリア |
| **Cmd+なんでも** | 素通り（コピペ・全選択等） |

## 必要条件

- macOS 15+ (Sequoia) — Apple Silicon (arm64)
- 起動中の vLLM インスタンス（デフォルト: `100.78.215.127:8000`、モデル: `spark-local`）
- LLMサーバーへのTailscale接続（ソース内の `inferenceURL` を変更すれば他のエンドポイントも可）

## インストール

### クイックインストール（gist経由）
```bash
bash <(curl -sL https://gist.githubusercontent.com/drikin/5136e194cf6e74695193317363e409af/raw/build-and-install.sh)
sudo cp -r /tmp/OneByte_Build/OneByte.app /Library/Input\ Methods/
sudo chmod -R 755 /Library/Input\ Methods/OneByte.app
sudo xattr -cr "/Library/Input Methods/OneByte.app"
```

その後、**システム設定 > キーボード > 入力ソース** で「OneByte」を追加。

### ソースからビルド
```bash
git clone https://github.com/drikin/OneByte.git
cd OneByte
bash build-and-install.sh
sudo cp -r /tmp/OneByte_Build/OneByte.app /Library/Input\ Methods/
sudo chmod -R 755 /Library/Input\ Methods/OneByte.app
sudo xattr -cr "/Library/Input Methods/OneByte.app"
```

## アーキテクチャ

OneByte は `handleEvent:client:` ですべてのキーイベントを一元管理（Apple推奨パターン）。`Cmd+` キーは即座に素通りさせ、それ以外は `DispatchQueue.main.sync` 経由で `@MainActor` で処理。変換は Swift Concurrency (`Task`) で非同期実行、タイムアウト3秒、エラー時はローマ字フォールバック。

```
handleEvent → handleOnMain → [キー蓄積]
                           → [Enter] → Task { LLMにPOST } → insertText
                           → [Tab]   → insertText(ローマ字)
```

### 設計判断
- **左右Cmdの判別**: 採用せず。`NSEvent.ModifierFlags.rightCommand` は実際には存在しないAPIだった。代わりに `Shift+Enter` で英訳。
- **文節配列** (`phrases:[String] + current:String`): Spaceで文節を区切り、LLMには連結した全文を渡すことで文脈を考慮した変換を実現。
- **端末上のフォールバック**: 未実装。LLMに繋がらない場合はローマ字をそのまま確定する。Mozcベースのローカル変換エンジンは将来の検討課題。

## LLMエンドポイントの設定

現在は `OneByteInputController.swift` にハードコードされています：

```swift
private let inferenceURL = URL(string: "http://YOUR_SERVER:PORT/v1/chat/completions")!
```

将来的には設定ファイルまたは `UserDefaults` で変更可能にする予定です。

## ライセンス

MIT
