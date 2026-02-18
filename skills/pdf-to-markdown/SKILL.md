---
name: pdf-to-markdown
description: PDF 파일을 마크다운으로 변환하고 검증합니다. PDF 문서를 마크다운 형식으로 변환하거나, 규칙/규정 문서를 구조화할 때 사용합니다.
disable-model-invocation: true
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
3. Write 도구로 `output/` 디렉토리에 저장합니다.
   - 파일명: PDF 파일명에서 확장자만 `.md`로 변경

### 2단계: 이미지 추출

extract_images.py로 이미지를 추출합니다 (조각 자동 합침, 벡터 포함, 캡션 인식):
```bash
python3 "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/scripts/extract_images.py" "<PDF경로>" -o "$MD_DIR/images" -v
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

## 큐 기반 배치 처리 (공유 큐)

여러 Claude Code 인스턴스가 동시에 작업할 수 있는 디렉토리 기반 공유 큐입니다.
동일 PC의 다른 터미널, 또는 클라우드 저장소를 통한 다른 PC에서도 병렬 작업이 가능합니다.

### 멀티 인스턴스 실행 방법

```bash
# 터미널 A (최초): 큐 초기화 + 배치 시작
/pdf-to-markdown init
/pdf-to-markdown start

# 터미널 B (추가): 초기화 없이 바로 배치 시작
/pdf-to-markdown start
```

- **큐 초기화(`init`)는 최초 1회만** 실행합니다. 이후 추가 터미널에서는 생략하고 바로 `start` 실행
- `init`을 다시 실행해도 기존 상태가 유지되고 신규 PDF만 추가 등록됩니다
- 각 인스턴스는 `hostname_pid-$$`로 고유 식별되어 작업 충돌이 발생하지 않습니다

### 큐 구조
```
/home/kimghw/kgc/.queue/
├── pending/       ← 대기 (.task 파일)
├── processing/    ← 작업 중 (mv로 원자적 할당)
├── done/          ← 완료
└── failed/        ← 실패
```

### 큐 관리 스크립트
모든 큐 작업은 `queue_manager.sh`를 통해 수행합니다:
```bash
bash "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/scripts/queue_manager.sh" <command>
```

| 명령 | 설명 |
|------|------|
| `init` | 미변환 PDF를 pending/에 등록 |
| `claim N` | N개 작업을 원자적으로 할당 |
| `complete name` | 작업 완료 처리 |
| `fail name msg` | 작업 실패 처리 |
| `release name` | 작업 반환 (pending으로) |
| `recover` | stale 작업 자동 복구 (30분 초과) |
| `status` | 전체 현황 출력 |
| `migrate` | 레거시 pdf-queue.txt 이전 |

### 배치 실행
1. 큐에서 N개 할당: `bash "$QUEUE_SCRIPT" claim N`
2. 각각에 대해 Task 도구로 백그라운드 에이전트 실행
3. 에이전트가 완료 시 `complete`, 실패 시 `fail` 호출

### 자동 연속 실행 (후크)
- **SubagentStop 후크**: 에이전트 완료 시 큐 상태 안내
- **Stop 후크**: 세션 종료 시 해당 인스턴스의 미완료 작업을 pending으로 자동 반환 (다른 인스턴스가 이어서 처리 가능)
- 항상 10개 에이전트가 병렬 실행되도록 유지
- **stale 복구**: `claim` 시 30분 초과 작업을 자동 감지하여 pending으로 반환

## 지원 파일

### 스크립트 (scripts/)
- [split_pdf.py](scripts/split_pdf.py): PDF 분할 스크립트 (11페이지 이상 → 10페이지씩)
- [extract_images.py](scripts/extract_images.py): 이미지 추출 스크립트 (조각 합침, 벡터 포함, 캡션 인식)
- [verify_markdown.py](scripts/verify_markdown.py): PDF-마크다운 검증 스크립트
- [queue_manager.sh](scripts/queue_manager.sh): 공유 큐 관리 스크립트

### 설정
- [config.sh](config.sh): 경로 설정 (새 프로젝트에서 이 파일만 수정)

### 문서
- [reference.md](reference.md): 시스템 상세 레퍼런스 (디렉토리 구조, 후크, 변환 규칙 등)
