#!/bin/bash
# 큐에 남은 작업이 있으면 다음 배치 실행 안내
# (공유 큐 - 디렉토리 기반)

# 설정 로드
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$PLUGIN_DIR/skills/pdf-to-markdown/config.sh" ]; then
    source "$PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
elif [ -n "$CLAUDE_PLUGIN_DIR" ]; then
    source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
fi

# 큐 디렉토리 확인
if [ ! -d "$QUEUE_PENDING" ]; then
    # 레거시 큐 감지
    if [ -f "$QUEUE_FILE_LEGACY" ] && [ -s "$QUEUE_FILE_LEGACY" ]; then
        echo "WARNING: 레거시 큐 파일 감지. /pdf-to-markdown migrate 로 이전하세요."
    fi
    exit 0
fi

# stale 작업 자동 복구
bash "$QUEUE_SCRIPT" recover 2>/dev/null | grep -c "RECOVERED" > /dev/null 2>&1 || true

# 상태 확인
pending=$(ls "$QUEUE_PENDING"/*.task 2>/dev/null | wc -l | tr -d ' ') || pending=0
processing=$(ls "$QUEUE_PROCESSING"/*.task 2>/dev/null | wc -l | tr -d ' ') || processing=0
done_count=$(ls "$QUEUE_DONE"/*.task 2>/dev/null | wc -l | tr -d ' ') || done_count=0
total_pdf=$(ls "$PDF_DIR"/*.pdf 2>/dev/null | wc -l | tr -d ' ') || total_pdf=0

if [ "$pending" -gt 0 ]; then
    echo "=== PDF 변환 큐 상태 ==="
    echo "완료: $done_count / $total_pdf"
    echo "작업중: $processing"
    echo "대기: $pending"
    echo ""
    echo "ACTION: 다음 작업을 할당받아 실행하세요."
    echo "  bash \"$QUEUE_SCRIPT\" claim 1"
elif [ "$processing" -gt 0 ]; then
    echo "=== PDF 변환 큐 상태 ==="
    echo "완료: $done_count / $total_pdf"
    echo "작업중: $processing"
    echo "대기: 0"
    echo ""
    echo "대기 작업 없음. ${processing}개 작업이 다른 인스턴스에서 처리중입니다."
fi
