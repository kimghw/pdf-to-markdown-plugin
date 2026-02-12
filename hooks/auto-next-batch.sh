#!/bin/bash
# 큐에 남은 작업이 있으면 다음 배치 실행 안내

# 설정 로드
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$PLUGIN_DIR/skills/pdf-to-markdown/config.sh" ]; then
    source "$PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
elif [ -n "$CLAUDE_PLUGIN_DIR" ]; then
    source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
fi

# 큐 파일 확인
if [ ! -f "$QUEUE_FILE" ]; then
    exit 0
fi

remaining=$(wc -l < "$QUEUE_FILE" | tr -d ' ')

if [ "$remaining" -gt 0 ]; then
    # 완료된 파일 수 확인
    completed=$(ls "$MD_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
    total=$(ls "$PDF_DIR"/*.pdf 2>/dev/null | wc -l | tr -d ' ')

    # 다음 실행할 파일들
    next_files=$(head -10 "$QUEUE_FILE" | tr '\n' ', ' | sed 's/,$//')

    echo "=== PDF 변환 큐 상태 ==="
    echo "완료: $completed / $total"
    echo "큐 대기: $remaining개"
    echo ""
    echo "ACTION: 다음 파일들을 백그라운드 에이전트로 실행하세요:"
    echo "$next_files"
    echo ""
    echo "실행 후 큐에서 제거: tail -n +11 $QUEUE_FILE > /tmp/q.txt && mv /tmp/q.txt $QUEUE_FILE"
fi
