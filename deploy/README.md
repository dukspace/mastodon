# 배포 흐름과 브랜치 운영

## 브랜치와 릴리스

| 대상                            | 역할                                                                      |
| ------------------------------- | ------------------------------------------------------------------------- |
| `codex/*`, `feature/*`, `fix/*` | 작업 브랜치. PR 대상은 `staging`                                          |
| `staging`                       | duk.space 커스텀 코드 통합. 병합하면 이미지 빌드 및 Synology Staging 배포 |
| `duk-v4.7.3-1` 등의 Git 태그    | 운영 릴리스로 선택한 커밋 표시. 태그 생성은 배포를 실행하지 않음          |
| GitHub Environment `staging`    | Synology 배포 설정과 이력                                                 |
| GitHub Environment `production` | 향후 운영 자동화의 설정과 이력. 현재 운영 배포는 수동 절차만 준비됨       |
| 기존 `production` 브랜치        | 이전 배포 흐름 보존용. 삭제하거나 새 작업을 병합하지 않음                 |
| `main`                          | 이번 전환에서 역할·내용을 변경하지 않음                                   |

공식 Mastodon 업데이트는 원하는 upstream 릴리스 태그에서 변경을 가져오는 작업 PR로
검토한다. 작업 PR을 `staging`에 병합한 후 그 **병합 결과 커밋**을 검증한다.
PR의 머리 커밋과 merge/squash 결과 SHA는 다를 수 있다.

배포 흐름:

```text
작업 브랜치 → PR → staging → 이미지 빌드 → Staging 배포·검증
                                      └→ 선택한 SHA의 동일 이미지 → 수동 Production 배포
```

이미지는 두 저장소에 `staging` 이동 태그와 `sha-<전체 SHA>` 태그로 게시한다.
`staging`은 확인 편의용이며 실제 자동 배포는 SHA 태그를 사용한다.
환경과 무관한 `dukspace` 빌드 메타데이터를 사용하므로 운영 승격을 위해 재빌드할 필요가 없다.
기존 `production` 이미지 태그를 삭제하지는 않지만 새 워크플로는 갱신하거나 사용하지 않는다.

운영 배포 대상은 최신 `staging` 또는 `production` HEAD를 따라가지 않는다.
검증한 SHA와 **Web/Streaming 두 이미지의 digest**를 기록하고 그 쌍을 사용한다.
SHA 태그를 다른 이미지로 덮어쓰지 않으며 운영에 승격한 이미지는 정리 대상에서 제외한다.
Git 릴리스 태그는 커밋 식별용이고, 실제 배포 완료 여부는 배포 기록으로 구분한다.

## 기존 production → staging 전환 절차

아래는 원격 설정과 NAS를 나중에 전환할 때의 절차다. 문서 추가나 로컬 브랜치 생성만으로
GitHub 설정, NAS checkout, 실행 중인 컨테이너는 바뀌지 않는다.
기존 브랜치에 있는 **이전 버전 워크플로는 여전히 production push에 반응**하므로
기존 `production` 브랜치는 보존하되 push/merge를 중단한다.

1. 기존 Staging 배포 작업이 끝났는지 확인하고 대기 작업을 정리한다.
   새 워크플로는 concurrency 그룹도 바뀌므로 두 버전의 배포가 겹치면 안 된다.
   전환 준비 중에는 NAS의 전용 runner를 잠시 offline으로 둔다.
   기존 앱 컨테이너는 계속 실행할 수 있다.
2. 최신 `origin/production`과 같은 커밋에서 원격 `staging` 브랜치를 만든다.
   `production`을 rename/delete하거나 force-push하지 않는다. 이미 만들어둔 로컬 `staging`이
   있다면 먼저 원격 최신 커밋과 일치하는지 확인한다.

   ```bash
   git fetch origin production
   # staging이 아직 없는 checkout에서만 실행
   git branch --no-track staging origin/production
   # 위 기준점을 확인한 후, 실제 원격 전환 시에만 실행
   git push origin staging
   ```

3. 작업 브랜치를 push하고 **base가 staging인 PR**을 만든다.
   `production` 보존 정책과 별개로 `staging`에는 PR/필수 CI 체크 규칙을 설정한다.
   PR의 기본 대상을 맞추려면 GitHub 기본 브랜치도 `staging`으로 설정할 수 있다.
4. GitHub Environment `staging`의 허용 배포 브랜치를 **staging만**으로 변경한다.
   기존 `production` 허용 규칙을 제거하되 Environment 자체는 삭제하지 않는다.
   기존 `STAGING_DEPLOY_PATH`, `STAGING_BASE_URL` 및 GHCR 접근 권한은 유지한다.
5. 이 변경의 PR을 `staging`에 병합한다. GitHub runner에서 검증·이미지 빌드가 성공하고
   해당 SHA의 두 이미지가 모두 존재하는지 확인한다. NAS runner가 offline이면 배포 job은 대기한다.
6. NAS의 기존 checkout을 다음과 같이 전환한다. 먼저 tracked 변경이 없는지 확인하고,
   변경이 있다면 중단해 보존한다. `.env.production`, DB/Redis 데이터, `public/system`을
   복사·교체·삭제하지 않는다.

   ```bash
   cd /volume1/docker/mastodon
   git status --short --untracked-files=no
   # tracked 변경이 없을 때만 계속 진행
   git fetch origin refs/heads/staging:refs/remotes/origin/staging
   git switch --track -c staging origin/staging
   # 이미 staging 브랜치가 있다면 위 switch -c 대신 아래 두 명령 사용
   # git switch staging
   # git merge --ff-only origin/staging
   ```

   NAS가 원래 single-branch clone이었더라도 명시적 refspec으로 staging을 가져온다.
   배포 스크립트도 같은 refspec을 사용한다. 기존 로컬 `production` 브랜치는 남겨둔다.

7. runner를 online으로 되돌린다. 가장 최신 `staging` 실행만 배포되는지와 공개 Web·Streaming
   smoke test 성공을 확인한다. 이전 SHA의 대기 job은 스크립트가 건너뛴다.
   필요하면 `Build images and deploy staging` 워크플로를 **staging ref**에서 수동 실행한다.
8. 최초 전환이 확인된 뒤에도 기존 `production` 브랜치는 당분간 보존한다.
   이 브랜치를 이후에 삭제할지는 별도 결정한다. Production 서버 배포는 이 전환에 포함하지 않는다.

## 운영 승격 및 긴급 수정

- [Staging 절차](staging/README.md)의 배포와 smoke test를 통과한 SHA를 선택한다.
  DB 리허설·UI·기능 검증도 별도로 완료한다.
- 선택한 SHA에 `duk-v4.7.3-1` 같은 릴리스 태그를 붙일 수 있다.
  태그를 push해도 이 구성에는 Production을 배포하는 워크플로가 없다.
- [Production 절차](production/README.md)에 따라 동일 이미지와 환경별 설정을 사용한다.
  실제 배포 전에 두 이미지의 digest가 기록한 값과 같은지 확인한다.
- 향후 자동화는 SHA를 입력받는 수동 실행으로 만들고 해당 SHA의 Staging 검증 성공을 확인한다.
  Production 배포용 job을 기존 Staging workflow에 자동으로 연결하지 않는다.
- 긴급 수정은 운영에 배포된 커밋에서 작업 브랜치를 만들고 수정 내용을 `staging`에도 반영한다.
  Staging에 아직 운영 반영할 수 없는 변경이 있다면 그 전체를 함께 승격하지 않는다.
  이때는 별도 후보 검증 절차를 먼저 마련한다. 현재 Staging 스크립트는 최신 `origin/staging`만 배포한다.

`.env.production`, `RAILS_ENV=production`, `NODE_ENV=production`은 Mastodon 실행 모드의
이름이므로 Staging에서도 유지한다. 실제 운영용 `deploy/production` 경로와
`mastodon-production` Compose 프로젝트 이름 역시 변경하지 않는다.
