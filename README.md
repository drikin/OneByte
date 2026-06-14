# OneByte

**2バイト言語で生きる私たちのためのIME。**

日本語をローマ字入力するすべての人が知っているあの苦労。

IMEに切り替えて、ローマ字を打ち、スペースを十数回叩いて変換候補を巡回する。文節区切りが間違ってることに気づいてBackspace。区切り直してまた変換。URLをコピーしようとして英数モードに切り替えるのを忘れて大文字が連打される——もう十分ではないでしょうか。

## きっかけ

2026年6月9日、[瀬戸弘司さん (@eguri89)](https://x.com/eguri89) が投稿したこのアイデアがすべての始まりでした——

> 従来のIMEではなく、AIを使ってローマ字を日本語に変換させる。

このポストは130万ビュー。「変換キーを叩かない日本語入力」という発想に多くの人が衝撃を受けました。OneByteはそのアイデアを、実際に毎日使えるIMEとして形にしたものです。

## 名前の由来

**OneByte** —— 「1バイトで済むなら2バイトの世界で苦しまなくていいじゃない」。

日本語（2バイト文字）を入力するために、いちいちIMEを切り替え、変換キーを叩き、候補を選ぶ。そんな2バイトの苦労を、ローマ字（1バイト文字）のまま入力してLLMに丸投げして解決する——という意味です。

「1バイトになりたい」——1バイト言語の人たちと同じように、変換作業なしでダイレクトに文字を入力したい。そこから転じて、**「だったら1バイトでいいじゃん」** と名付けました。

OneByteは50年前から変わらないIMEのパラダイムをぶち壊します。

**ローマ字を打つ。Enterを押す。日本語が出る。**

打ち間違い、抜け文字、不正確な文節区切り——全部LLMが一発で直します。変換候補ウィンドウも、モード切り替えも、スペース連打も必要ありません。

英語が欲しいなら **Shift+Enter。** 一発英訳。

Swift + Input Method Kit で構築。バックエンドはローカルLLM（DGX Spark クラスタ上の vLLM）。

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

| キー | 動作 | カテゴリ |
|---|---|---|
| **Enter** | 全文を日本語に変換・確定 | 変換 |
| **Shift+Enter** | 日本語にしてから英訳・確定 | 変換 |
| **Tab** | ローマ字のまま確定（LLMを通さない） | 変換 |
| **Space** | 文節区切り（長文を分割したいときに） | 編集 |
| **Backspace** | 1文字削除 / 前の文節に戻る | 編集 |
| **Escape** | 全文クリア | 編集 |
| **Cmd+任意** | アプリへ素通り（コピペ・全選択等） | パススルー |
|| **Ctrl+J** | 直接入力モードON/OFFトグル（英字を直接打ちたいとき） | モード切替 |

## 必要条件

- macOS 15+ (Sequoia) — Apple Silicon (arm64)
- 起動中の vLLM サーバーインスタンス（デフォルト: `100.78.215.127:8000`、モデル: `spark-local`）
- LLMサーバーへのネットワーク接続（ソース内の `inferenceURL` を変更すれば他のエンドポイントも可）

**バックエンドの選択肢（参考）:**
- **Ollama** — 最も手軽。Apple Silicon上のローカルLLMなら `ollama pull <model>` で即座に起動
- **LM Studio** — GUIでモデル管理。ローカルサーバーとしても使える
- **vLLM** — OneByte開発環境で使用。DGX Sparkクラスタ上で動作
- **MLX** — Apple Silicon特化。MPSバックエンドで効率的

## インストール

```bash
git clone https://github.com/drikin/OneByte.git
cd OneByte
bash build-and-install.sh
```

```bash
# ビルドが成功したらインストール
sudo cp -r "/tmp/OneByte_Build/OneByte.app" "/Library/Input Methods/"
sudo chmod -R 755 "/Library/Input Methods/OneByte.app"
# Gatekeeperの実行制限を解除（署名なしアプリ向け）
sudo xattr -cr "/Library/Input Methods/OneByte.app"
```

インストール後、**システム設定 > キーボード > 入力ソース** を開き、「OneByte」を追加してください。

**ログアウト／再起動が必要な場合があります。**

## アーキテクチャ

OneByte は `handleEvent:client:` ですべてのキーイベントを一元管理（Apple推奨パターン）。`Cmd+` キーは即座に素通りさせ、それ以外は `DispatchQueue.main.sync` 経由で処理（※`@MainActor`境界を安全に越えるための意図的な設計。`sync`を使うのは `handleEvent` の戻り値を即座に返す必要があるため）。変換は Swift Concurrency (`Task`) で非同期実行、タイムアウト3秒、エラー時はローマ字フォールバック。

```
handleEvent → handleOnMain → [キー蓄積]
                           → [Enter] → Task { LLMにPOST } → insertText
                           → [Tab]   → insertText(ローマ字)
```

### 設計判断
- **左右Cmdの判別**: 採用せず。`NSEvent.ModifierFlags.rightCommand` は実際には存在しないAPIだった（キーコードベースの判別も誤検知が多く断念）。代わりに `Shift+Enter` で英訳。
- **文節配列** (`phrases:[String] + current:String`): Spaceで文節を区切り、LLMには連結した全文を渡すことで文脈を考慮した変換を実現。
- **端末上のフォールバック**: 未実装。LLMに繋がらない場合はローマ字をそのまま確定する。Mozcベースのローカル変換エンジンは将来の検討課題。
- **isActiveフラグ**: `deactivateServer` 時にフラグを落とし、ゾンビTaskによるclient参照を防止。
- **phrases上限（20件）**: メモリ消費とLLMプロンプト長の制御のため、超えたら古いものから削除。

## LLMエンドポイントの設定

OneByteはデフォルトで OpenAI API（`gpt-4o-mini`）を使用します。APIキーが設定されていない場合、リクエストは認証なしで送信されます。

**ターミナルで設定（永続化）:**

| キー | 説明 | デフォルト |
|---|---|---|
| `OneByteEndpoint` | LLM APIエンドポイントURL | `https://api.openai.com/v1/chat/completions` |
| `OneByteAPIKey` | Bearer認証トークン（空なら未設定） | なし |
| `OneByteModel` | モデル名 | `gpt-4o-mini` |

```bash
# 例: OpenAI
defaults write com.drikin.inputmethod.OneByte OneByteEndpoint "https://api.openai.com/v1/chat/completions"
defaults write com.drikin.inputmethod.OneByte OneByteAPIKey "sk-xxxxx"
defaults write com.drikin.inputmethod.OneByte OneByteModel "gpt-4o-mini"

# 例: ローカルvLLM
defaults write com.drikin.inputmethod.OneByte OneByteEndpoint "http://localhost:8000/v1/chat/completions"
defaults write com.drikin.inputmethod.OneByte OneByteModel "qwen"

# 確認
defaults read com.drikin.inputmethod.OneByte
```

変更後は **ログアウト／ログイン** または OneByte プロセスを再起動してください。

## ライセンス

MIT
