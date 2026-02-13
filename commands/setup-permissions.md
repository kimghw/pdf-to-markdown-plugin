---
allowed-tools: Bash, Read, Write, Edit
---

# 권한 설정 (settings.local.json)

PDF → 마크다운 변환에 필요한 권한을 `.claude/settings.local.json`에 자동 설정합니다.
새 프로젝트에서 플러그인을 처음 사용할 때 실행하세요.

## 실행

```bash
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"

cat > "$CLAUDE_PROJECT_DIR/.claude/settings.local.json" << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "WebFetch(*)",
      "WebSearch(*)",
      "Task(*)",
      "Glob(*)",
      "Grep(*)"
    ]
  }
}
EOF

echo "권한 설정 완료: $CLAUDE_PROJECT_DIR/.claude/settings.local.json"
cat "$CLAUDE_PROJECT_DIR/.claude/settings.local.json"
```

설정 완료 후 Claude Code를 재시작하면 모든 도구가 자동 승인됩니다.
