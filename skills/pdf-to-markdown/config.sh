#!/bin/bash
# PDF → 마크다운 변환 플러그인 설정
# 새 프로젝트에서 사용 시 이 파일의 경로만 수정하면 됩니다.

# 프로젝트 루트 (자동 감지)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"

# 플러그인 루트 (자동 감지)
PLUGIN_DIR="${CLAUDE_PLUGIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# PDF/마크다운 경로
PDF_DIR="$PROJECT_DIR/KR_강선규칙_2025/분할"
MD_DIR="$PROJECT_DIR/KR_강선규칙_2025/마크다운"
IMG_DIR="$MD_DIR/images"

# 큐 파일
QUEUE_FILE="$PROJECT_DIR/.claude/pdf-queue.txt"

# 스킬 디렉토리
SKILL_DIR="$PLUGIN_DIR/skills/pdf-to-markdown"
