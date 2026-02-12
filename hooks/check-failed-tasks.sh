#!/bin/bash
# 완료된 PDF 변환 작업 중 실패한 항목 확인

# 설정 로드
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$PLUGIN_DIR/skills/pdf-to-markdown/config.sh" ]; then
    source "$PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
elif [ -n "$CLAUDE_PLUGIN_DIR" ]; then
    source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
fi

# 변환된 마크다운 파일 목록
converted=()
failed=()

for pdf in "$PDF_DIR"/*.pdf; do
    if [ -f "$pdf" ]; then
        basename=$(basename "$pdf" .pdf)
        md_file="$MD_DIR/${basename}.md"

        if [ -f "$md_file" ]; then
            # 파일 크기 확인 (최소 1KB 이상이어야 정상)
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

if [ $remaining -gt 0 ] && [ $remaining -le 20 ]; then
    echo ""
    echo "=== 미처리 항목 (처음 20개) ==="
    count=0
    for pdf in "$PDF_DIR"/*.pdf; do
        basename=$(basename "$pdf" .pdf)
        md_file="$MD_DIR/${basename}.md"
        if [ ! -f "$md_file" ]; then
            echo "  - $basename"
            count=$((count + 1))
            if [ $count -ge 20 ]; then
                break
            fi
        fi
    done
fi
