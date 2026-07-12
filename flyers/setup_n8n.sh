#!/bin/bash
# ─────────────────────────────────────────────────────────
# まなちゃんヒアリング n8n セットアップスクリプト
# 実行: bash setup_n8n.sh
# ─────────────────────────────────────────────────────────
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
N8N_URL="http://localhost:5678"
N8N_USER="admin@nerufirm.com"
N8N_PASS="changeme123!"
WORKFLOW_JSON="$DIR/n8n_workflow.json"
HTML_FILE="$DIR/manami_questionnaire.html"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  まなちゃんヒアリング n8n セットアップ"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 1. n8n が起動しているか確認 ──
echo "[1/4] n8n の起動確認..."
if ! curl -sf "$N8N_URL/healthz" > /dev/null 2>&1; then
  echo "  → n8n を起動します..."
  export N8N_BASIC_AUTH_ACTIVE=true
  export N8N_BASIC_AUTH_USER="$N8N_USER"
  export N8N_BASIC_AUTH_PASSWORD="$N8N_PASS"
  export N8N_SECURE_COOKIE=false
  export WEBHOOK_URL="$N8N_URL/"
  export N8N_USER_MANAGEMENT_DISABLED=true
  n8n start &
  N8N_PID=$!
  echo "  → PID: $N8N_PID"
  echo "  → 起動待機中（最大30秒）..."
  for i in $(seq 1 30); do
    if curl -sf "$N8N_URL/healthz" > /dev/null 2>&1; then
      echo "  ✓ n8n 起動完了"
      break
    fi
    sleep 1
  done
else
  echo "  ✓ n8n はすでに起動しています"
fi

# ── 2. オーナーアカウント作成（初回のみ） ──
echo ""
echo "[2/4] オーナーアカウントのセットアップ..."
SETUP_RESP=$(curl -sf -X POST "$N8N_URL/api/v1/owner/setup" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$N8N_USER\",\"firstName\":\"Sato\",\"lastName\":\"Nerufirm\",\"password\":\"$N8N_PASS\"}" 2>/dev/null || echo "already_setup")

if echo "$SETUP_RESP" | grep -q "already_setup"; then
  echo "  → すでにセットアップ済みです"
else
  echo "  ✓ オーナーアカウント作成完了"
fi

# ── 3. APIキー取得 ──
echo ""
echo "[3/4] APIキーを取得..."
LOGIN_RESP=$(curl -sf -c /tmp/n8n_cookies.txt -X POST "$N8N_URL/api/v1/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$N8N_USER\",\"password\":\"$N8N_PASS\"}" 2>/dev/null)

TOKEN=$(echo "$LOGIN_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))" 2>/dev/null || echo "")

if [ -z "$TOKEN" ]; then
  echo "  ⚠ トークン取得失敗。n8n UI で手動インポートしてください:"
  echo "  → $N8N_URL"
  echo "  → Workflows > Import from file > $WORKFLOW_JSON"
  exit 1
fi
echo "  ✓ ログイン成功"

# ── 4. ワークフロー インポート ──
echo ""
echo "[4/4] ワークフローをインポート..."
IMPORT_RESP=$(curl -sf -X POST "$N8N_URL/api/v1/workflows" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d @"$WORKFLOW_JSON" 2>/dev/null)

WORKFLOW_ID=$(echo "$IMPORT_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || echo "")

if [ -z "$WORKFLOW_ID" ]; then
  echo "  ⚠ インポート失敗。手動でインポートしてください:"
  echo "  → $N8N_URL/workflows"
  exit 1
fi

# ── アクティベート ──
curl -sf -X PATCH "$N8N_URL/api/v1/workflows/$WORKFLOW_ID" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"active":true}' > /dev/null 2>&1

WEBHOOK_URL="$N8N_URL/webhook/manami-hearing"
echo "  ✓ ワークフロー ID: $WORKFLOW_ID"
echo "  ✓ Webhook URL: $WEBHOOK_URL"

# ── HTMLに Webhook URL を書き込む ──
sed -i '' "s|YOUR_N8N_WEBHOOK_URL|$WEBHOOK_URL|g" "$HTML_FILE"
echo "  ✓ HTML に Webhook URL を設定しました"

# ── 完了メッセージ ──
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ セットアップ完了！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  🔑 n8n 管理画面:  $N8N_URL"
echo "  📧 ログイン:      $N8N_USER / $N8N_PASS"
echo "  📡 Webhook URL:   $WEBHOOK_URL"
echo ""
echo "  ━ 次に行うこと（n8n UI で設定） ━"
echo ""
echo "  1. Google Sheets の認証情報を追加"
echo "     Credentials > New > Google Sheets OAuth2"
echo "     → YOUR_GOOGLE_SHEET_ID をシートIDに変更"
echo ""
echo "  2. Slack の認証情報を追加"
echo "     Credentials > New > Slack OAuth2"
echo "     → #YOUR_SLACK_CHANNEL をチャンネル名に変更"
echo ""
echo "  3. フォームをまなちゃんに送る"
echo "     ファイル: $HTML_FILE"
echo ""
