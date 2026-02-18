#!/bin/bash
# 세션 종료 시 변환 현황 보고 및 작업 반환
# (공유 큐 - 디렉토리 기반)

# 설정 로드
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$PLUGIN_DIR/skills/pdf-to-markdown/config.sh" ]; then
    source "$PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
elif [ -n "$CLAUDE_PLUGIN_DIR" ]; then
    source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
fi

# 공유 큐 디렉토리가 있으면 사용
if [ -d "$QUEUE_DIR" ]; then
    # 이 인스턴스가 처리중인 작업을 반환
    for taskfile in "$QUEUE_PROCESSING"/*.task; do
        [ -f "$taskfile" ] || continue
        claimed_by=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get('claimed_by', ''))
except (json.JSONDecodeError, ValueError):
    with open(sys.argv[1]) as f:
        for line in f:
            if line.strip().startswith('claimed_by='):
                print(line.strip().split('=', 1)[1])
                sys.exit(0)
    print('')
" "$taskfile" 2>/dev/null)
        if [ "$claimed_by" = "$INSTANCE_ID" ]; then
            name=$(basename "$taskfile" .task)
            # 변환이 실제로 완료되었는지 확인
            md="$MD_DIR/${name}.md"
            if [ -f "$md" ]; then
                size=$(stat -c%s "$md" 2>/dev/null || stat -f%z "$md" 2>/dev/null || echo 0)
                if [ "$size" -ge 1000 ]; then
                    bash "$QUEUE_SCRIPT" complete "$name" 2>/dev/null
                    continue
                fi
            fi
            # 미완료 → pending으로 반환
            bash "$QUEUE_SCRIPT" release "$name" 2>/dev/null
        fi
    done

    # 전체 현황 출력
    bash "$QUEUE_SCRIPT" status
    exit 0
fi

# --- 레거시 방식 (큐 디렉토리가 없을 때) ---

converted=()
failed=()

for pdf in "$PDF_DIR"/*.pdf; do
    if [ -f "$pdf" ]; then
        basename=$(basename "$pdf" .pdf)
        md_file="$MD_DIR/${basename}.md"

        if [ -f "$md_file" ]; then
            size=$(stat -f%z "$md_file" 2>/dev/null || stat -c%s "$md_file" 2>/dev/null)
            if [ "$size" -lt 1000 ]; then
                failed+=("$basename (파일 크기 부족: ${size}B)")
            else
                converted+=("$basename")
            fi
        fi
    fi
done

total_pdf=$(ls "$PDF_DIR"/*.pdf 2>/dev/null | wc -l)
total_converted=${#converted[@]}
total_failed=${#failed[@]}
remaining=$((total_pdf - total_converted - total_failed))

echo "=== PDF → 마크다운 변환 현황 ==="
echo "총 PDF: $total_pdf개"
echo "변환 완료: $total_converted개"
echo "실패/문제: $total_failed개"
echo "미처리: $remaining개"

if [ $total_failed -gt 0 ]; then
    echo ""
    echo "=== 실패/문제 항목 ==="
    for item in "${failed[@]}"; do
        echo "  - $item"
    done
fi
