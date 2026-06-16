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

アクティブなアプリ名（Xcode、ブラウザなど）を自動検出し、変換に反映します。直前の変換履歴も文脈として使われ、より自然な日本語に。もしLLMに繋がらない場合は⚠️マークが一瞬表示され、その後ローマ字がそのまま確定されます。

## キーバインド

| キー | 動作 |
|---|---|
| **Enter** | 全文を日本語に変換・確定 |
| **Shift+Enter** | 日本語にしてから英訳・確定 |
| **Tab** | ローマ字のまま確定（LLMを通さない） |
| **Space** | 文節区切り（長文を分割したいときに） |
| **Ctrl+J** | 直接入力モードON/OFF（英字を直接打ちたいとき） |
| **Backspace** | 1文字削除 / 前の文節に戻る |
| **Escape** | 全文クリア |
| **Cmd+任意** | アプリへ素通り（コピペ・全選択等） |

## 必要条件

- macOS 15+ (Sequoia) — Apple Silicon (arm64)
- 起動中の LLM API サーバー（デフォルト: Spark2 vLLM）

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
sudo xattr -cr "/Library/Input Methods/OneByte.app"
```

インストール後、**システム設定 > キーボード > 入力ソース** を開き、「OneByte」を追加してください。**ログアウト／再起動が必要な場合があります。**

## LLMの設定

メニューバーのOneByteアイコン → **設定...** から、LLMのエンドポイント・APIキー・モデル名を変更できます。

**デフォルト:** Spark2 vLLM（`spark-local`、自宅LAN）

| フィールド | 説明 |
|---|---|
| API Endpoint | LLM APIのURL（OpenAI互換） |
| API Key | Bearer認証トークン（空欄可） |
| Model | モデル名 |

**プリセット:**
- **Spark2 vLLM** — 自宅のDGX Sparkクラスタ（最速・無料）
- **OpenAI GPT-4o-mini** — クラウド、APIキーが必要
- **Ollama ローカル** — `localhost:11434` で動くOllama

### ターミナルから設定する場合

```bash
# OpenAI に変更
defaults write com.drikin.inputmethod.OneByte OneByteEndpoint "https://api.openai.com/v1/chat/completions"
defaults write com.drikin.inputmethod.OneByte OneByteAPIKey "sk-xxxxx"
defaults write com.drikin.inputmethod.OneByte OneByteModel "gpt-4o-mini"

# ローカルvLLM に変更
defaults write com.drikin.inputmethod.OneByte OneByteEndpoint "http://localhost:8000/v1/chat/completions"
defaults write com.drikin.inputmethod.OneByte OneByteModel "qwen"

# 確認
defaults read com.drikin.inputmethod.OneByte
```

## アーキテクチャ

OneByte は `handleEvent:client:` ですべてのキーイベントを一元管理（Apple推奨パターン）。`Cmd+` キー・`Ctrl+J` の直接入力モード時は即座に素通りさせ、それ以外は `DispatchQueue.main.sync` 経由で処理。変換は Swift Concurrency (`Task`) で非同期実行、タイムアウト3秒、エラー時はローマ字フォールバック。

```
handleEvent → handleOnMain → [キー蓄積]
                           → [Enter] → Task { LLMにPOST } → insertText
                           → [Tab]   → insertText(ローマ字)
```

### 設計判断

- **Ctrl+J トグル**: CapsLockに頼らず、IMEだけで完結する直接入力モード。CapsLockはOSの入力ソース切替機能を使えばOneByte ↔ U.S.を切り替え可能。
- **文節配列** (`phrases:[String] + current:String`): Spaceで文節を区切り、LLMには連結した全文を渡すことで文脈を考慮した変換を実現。
- **変換中のキー入力ブロックなし**: `converting` フラグは変換の二重トリガー防止のみに使用。キー入力は常に受け付ける。
- **LLMエンドポイントのカスタマイズ**: 設定画面（SwiftUI）からエンドポイント・APIキー・モデルを変更可能。設定は `UserDefaults` に保存され、次回変換から即座に反映。
- **変換のフォールバック**: LLMに繋がらない場合（タイムアウト・エラー）、ローマ字をそのまま確定する。常に動く。

## ユーザー辞書

よく使う固有名詞や定型表現を登録できます。辞書に登録された単語はLLMを通さず**必ず正しく変換**されます。

**設定方法:**

```bash
# JSONファイルを直接編集
mkdir -p ~/.onebyte
cat > ~/.onebyte/user_dict.json <<EOF
{
  "drikin": "ドリキン",
  "backspacefm": "バックスペースエフエム",
  "eguri": "えぐり"
}
EOF
```

- キーは大文字小文字を区別しません（`Drikin` = `drikin`）
- 辞書ファイルは自動的に読み込まれ、変更は即座に反映されます
- キーは半角英数のみ推奨（それ以外は未テスト）

## ライセンス

MIT
