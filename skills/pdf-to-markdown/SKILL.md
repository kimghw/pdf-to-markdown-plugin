---
name: pdf-to-markdown
description: PDF 파일을 마크다운으로 변환하고 검증합니다. PDF 문서를 마크다운 형식으로 변환하거나, 규칙/규정 문서를 구조화할 때 사용합니다.
---

# PDF to Markdown Converter

PDF 파일을 마크다운으로 변환하고 검증합니다.
11페이지 이상의 PDF는 자동으로 10페이지씩 분할합니다.

## 작업 단계

### 0단계: PDF 분할 (11페이지 이상인 경우)

`$ARGUMENTS`가 폴더 경로이면 해당 폴더 내 모든 PDF를, 파일 경로이면 해당 파일을 대상으로 합니다.

각 PDF의 페이지 수를 확인하여 11페이지 이상이면 10페이지씩 분할합니다:

```bash
python3 "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/scripts/split_pdf.py" "$ARGUMENTS"
```

분할 결과:
- `원본파일명_0001-0010.pdf`, `원본파일명_0011-0020.pdf`, ...
- 분할된 파일은 원본과 같은 디렉토리에 저장
- 10페이지 이하인 파일은 그대로 유지

### 1단계: PDF 읽기 및 마크다운 변환

1. Read 도구로 PDF 파일을 읽습니다 (분할된 경우 각 분할 파일을 순서대로)
2. PDF 내용을 분석하여 구조화된 마크다운으로 변환합니다:
   - 제목은 `#`, `##`, `###` 등으로 계층 구조 표현
   - 조항 번호 (101., 102. 등)는 `###`로 표기
   - 용어 정의는 `**용어**` 형식으로 굵게 표시
   - 목록은 `-` 또는 숫자 목록 사용
   - 표는 마크다운 표 문법 사용
   - 이미지는 `![설명](images/파일명.png)` 형식
3. Write 도구로 `마크다운/` 디렉토리에 저장합니다.
   - 파일명: PDF 파일명에서 확장자만 `.md`로 변경

### 2단계: 이미지 추출

extract_images.py로 이미지를 추출합니다 (조각 자동 합침, 벡터 포함, 캡션 인식):
```bash
python3 "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/scripts/extract_images.py" "<PDF경로>" -o "마크다운/images" -v
```

### 3단계: 검증

검증 스크립트를 실행합니다:
```bash
python3 "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/scripts/verify_markdown.py" "<PDF경로>" "<MD경로>" -v
```

### 4단계: 재검토 (필요시)

검증 결과에서 누락 의심 항목이 있으면:
1. 해당 항목들을 확인합니다.
2. 실제 누락인 경우 마크다운을 수정합니다.
3. 형식 차이(머리글/바닥글, 괄호 종류 등)인 경우 무시합니다.

## 출력

작업 완료 후 다음을 보고합니다:
- 분할된 PDF 파일 수 (분할한 경우)
- 생성된 마크다운 파일 경로
- 추출된 이미지 개수 (있는 경우)
- 검증 결과 (커버리지 %, 누락 의심 항목 수)

## 큐 기반 배치 처리

여러 PDF를 순차/병렬로 처리할 때는 큐를 사용합니다.

### 큐 파일
`$CLAUDE_PROJECT_DIR/.claude/pdf-queue.txt` (한 줄에 파일명 하나, 확장자 제외)

### 큐 초기화
경로는 `config.sh`에서 읽습니다:
```bash
source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
for pdf in "$PDF_DIR"/*.pdf; do
  basename=$(basename "$pdf" .pdf)
  md="$MD_DIR/${basename}.md"
  [ ! -f "$md" ] && echo "$basename"
done | sort > "$QUEUE_FILE"
```

### 배치 실행
1. 큐에서 N개 가져오기: `head -N "$CLAUDE_PROJECT_DIR/.claude/pdf-queue.txt"`
2. 각각에 대해 Task 도구로 백그라운드 에이전트 실행
3. 큐에서 제거: `tail -n +$((N+1)) queue.txt > /tmp/q.txt && mv /tmp/q.txt queue.txt`

### 자동 연속 실행 (후크)
- **SubagentStop 후크**: 에이전트 완료 시 `auto-next-batch.sh` 실행 → 큐에 남은 작업 안내
- **Claude가 안내를 보고 다음 에이전트 자동 실행**
- 항상 10개 에이전트가 병렬 실행되도록 유지

## 지원 파일

### 스크립트 (scripts/)
- [split_pdf.py](scripts/split_pdf.py): PDF 분할 스크립트 (11페이지 이상 → 10페이지씩)
- [extract_images.py](scripts/extract_images.py): 이미지 추출 스크립트 (조각 합침, 벡터 포함, 캡션 인식)
- [verify_markdown.py](scripts/verify_markdown.py): PDF-마크다운 검증 스크립트

### 설정
- [config.sh](config.sh): 경로 설정 (새 프로젝트에서 이 파일만 수정)

### 문서
- [reference.md](reference.md): 시스템 상세 레퍼런스 (디렉토리 구조, 후크, 변환 규칙 등)
