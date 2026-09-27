# DB Schema - Continuum

- 데이터베이스: sqlite

## 테이블
공통: SQLite `TEXT` ID는 stable ID이며 이름 변경과 무관하다. 시간은 UTC ISO-8601 text다. Schema version 3은 앱 시작 시 자동 생성하고 version 1·2 사용자 DB는 명시적 migration을 거친다. World draft 자동 저장은 metadata, Player/Opening, ordered rules, Lore/Character/Location 변경을 하나의 transaction에서 동기화한다. 첫 실행 샘플 World와 one-time marker도 단일 transaction으로 기록한다.

### app_metadata
- 목적: 최초 실행 기본 콘텐츠 설치 여부 등 앱 수준 영속 상태. 담당: `features/world/data`. Soft delete: 아니오.

| Column | Type | Required | Default | Index | Unique | Description |
| --- | --- | --- | --- | --- | --- | --- |
| key | TEXT | 예 | 없음 | PK | 예 | 앱 metadata 항목 키 |
| value | TEXT | 예 | 없음 | 없음 | 아니오 | `default_world_seed_v1` 값: 설치한 샘플 World ID 또는 기존 라이브러리 보존 표시 |

### worlds
- 목적: World metadata. 담당: `features/world/data`. Soft delete: 아니오.

| Column | Type | Required | Default | Index | Unique | Description |
| --- | --- | --- | --- | --- | --- | --- |
| id | TEXT | 예 | 없음 | PK | 예 | stable world ID |
| name | TEXT | 예 | 없음 | 없음 | 아니오 | 필수 이름 |
| description | TEXT | 예 | 없음 | 없음 | 아니오 | 설명 |
| genres | TEXT | 예 | 빈 값 | 없음 | 아니오 | URI encoded genre 목록, U+001F 구분 |
| tones | TEXT | 예 | 빈 값 | 없음 | 아니오 | URI encoded tone 목록, U+001F 구분 |
| created_at | TEXT | 예 | 없음 | 없음 | 아니오 | 생성 시각 |
| updated_at | TEXT | 예 | 없음 | `idx_worlds_updated` | 아니오 | 최근 수정 시각 |
| player_name | TEXT | 예 | 빈 값 | 없음 | 아니오 | Player 표시 이름 |
| player_description | TEXT | 예 | 빈 값 | 없음 | 아니오 | Player 설명 |
| player_background | TEXT | 예 | 빈 값 | 없음 | 아니오 | Player 배경 |
| player_traits | TEXT | 예 | 빈 값 | 없음 | 아니오 | URI encoded trait 목록, U+001F 구분 |
| opening_location_id | TEXT | 아니오 | NULL | 없음 | 아니오 | 시작 Location stable ID; definition 참조라 FK 미적용 |
| opening_character_ids | TEXT | 예 | 빈 값 | 없음 | 아니오 | URI encoded Character ID 목록 |
| opening_situation | TEXT | 예 | 빈 값 | 없음 | 아니오 | 시작 상황 텍스트 |

### world_rules
- 목적: World의 순서가 있는 텍스트 규칙. 담당: `features/world/data`. Soft delete: 아니오.

| Column | Type | Required | Default | Index | Unique | Description |
| --- | --- | --- | --- | --- | --- | --- |
| id | TEXT | 예 | 없음 | PK | 예 | stable rule row ID |
| world_id | TEXT | 예 | 없음 | FK | 아니오 | worlds 참조 |
| position | INTEGER | 예 | 없음 | UNIQUE(world_id, position) | world 내 고유 | 표시 순서 |
| text | TEXT | 예 | 없음 | 없음 | 아니오 | rule text |

### lore_entries
- 목적: Lore 문서. 담당: `features/world/data`. Soft delete: 아니오.

| Column | Type | Required | Default | Index | Unique | Description |
| --- | --- | --- | --- | --- | --- | --- |
| id | TEXT | 예 | 없음 | PK | 예 | stable lore ID |
| world_id | TEXT | 예 | 없음 | FK, `idx_lore_world` | 아니오 | owner world |
| title | TEXT | 예 | 없음 | 없음 | 아니오 | 제목 |
| category | TEXT | 예 | `History` | 없음 | 아니오 | 자유 문자열 category |
| content | TEXT | 예 | 빈 값 | 없음 | 아니오 | 문서 내용 |
| created_at | TEXT | 예 | 없음 | 없음 | 아니오 | 생성 시각 |
| updated_at | TEXT | 예 | 없음 | 없음 | 아니오 | 수정 시각 |

### characters
- 목적: Character definition(runtime state 제외). 담당: `features/world/data`. Soft delete: 아니오.

| Column | Type | Required | Default | Index | Unique | Description |
| --- | --- | --- | --- | --- | --- | --- |
| id | TEXT | 예 | 없음 | PK | 예 | stable character ID |
| world_id | TEXT | 예 | 없음 | FK, `idx_characters_world` | 아니오 | owner world |
| name, role, description, appearance, personality, background | TEXT | 예 | 빈 값 | 없음 | 아니오 | definition fields |
| public_information, secret_information | TEXT | 예 | 빈 값 | 없음 | 아니오 | 공개/비공개 설정 |
| portrait_asset_id | TEXT | 아니오 | NULL | 없음 | 아니오 | 향후 asset reference |
| created_at, updated_at | TEXT | 예 | 없음 | 없음 | 아니오 | 생성/수정 시각 |

### locations
- 목적: 계층형 Location definition. 담당: `features/world/data`. Soft delete: 아니오.

| Column | Type | Required | Default | Index | Unique | Description |
| --- | --- | --- | --- | --- | --- | --- |
| id | TEXT | 예 | 없음 | PK | 예 | stable location ID |
| world_id | TEXT | 예 | 없음 | FK, `idx_locations_world_parent` | 아니오 | owner world |
| name, description | TEXT | 예 | 빈 값 | 없음 | 아니오 | definition fields |
| parent_location_id | TEXT | 아니오 | NULL | self FK | 아니오 | 같은 world의 parent |
| background_asset_id | TEXT | 아니오 | NULL | 없음 | 아니오 | 향후 asset reference |
| created_at, updated_at | TEXT | 예 | 없음 | 없음 | 아니오 | 생성/수정 시각 |

### campaigns
- 목적: 한 World에서 진행 중인 서로 독립된 플레이 기록. 담당: `features/world/data`. Soft delete: 아니오.

| Column | Type | Required | Default | Index | Unique | Description |
| --- | --- | --- | --- | --- | --- | --- |
| id | TEXT | 예 | 없음 | PK | 예 | Campaign stable ID |
| world_id | TEXT | 예 | 없음 | FK, `idx_campaigns_world` | 아니오 | worlds 참조; World 삭제 시 CASCADE |
| payload | TEXT | 예 | 없음 | 없음 | 아니오 | Campaign schema v1 JSON: WorldState (current location, present characters, optional time/atmosphere/relevant objects, facts, events, turn), current SceneTurn, history, and Character memory (known facts, important memories, relationship, current emotion, goals, recent events). Optional fields default empty when loading older payloads. |
| updated_at | TEXT | 예 | 없음 | 없음 | 아니오 | 마지막 저장 시각 |
| last_played_at | TEXT | 예 | 없음 | `idx_campaigns_world` | 아니오 | Library Continue 정렬 기준 |

### language_model_settings
- 목적: 비밀이 아닌 OpenAI-compatible provider 설정. 담당: `features/world/data`. Soft delete: 해당 없음.

| Column | Type | Required | Default | Index | Unique | Description |
| --- | --- | --- | --- | --- | --- | --- |
| id | INTEGER | 예 | 1 | PK, CHECK(id=1) | 예 | 단일 사용자 설정 row |
| base_url | TEXT | 예 | 없음 | 없음 | 아니오 | Provider base URL; 미저장 시 repository가 로컬 기본값 반환 |
| model | TEXT | 예 | 없음 | 없음 | 아니오 | 선택된 모델 ID |
| temperature | REAL | 예 | 없음 | 없음 | 아니오 | 생성 temperature, 0..2 |
| context_limit | INTEGER | 예 | 없음 | 없음 | 아니오 | 예상 context budget |

API key는 이 table에 저장하지 않고 프로세스 메모리에서만 유지한다.

## 관계
| From | To | Cardinality | Delete Behavior | Notes |
| --- | --- | --- | --- | --- |
| worlds.id | world_rules.world_id | 1:N | CASCADE | 규칙 순번은 world 내 고유 |
| worlds.id | lore_entries.world_id | 1:N | CASCADE | 월드 삭제 시 함께 삭제 |
| worlds.id | characters.world_id | 1:N | CASCADE | 월드 삭제 시 함께 삭제 |
| worlds.id | locations.world_id | 1:N | CASCADE | 월드 삭제 시 함께 삭제 |
| locations.id | locations.parent_location_id | 1:N | CASCADE | sibling/descendant 계층; same-world 및 cycle 방지 trigger |
| worlds.id | campaigns.world_id | 1:N | CASCADE | 여러 Campaign; World 삭제 시 플레이 기록도 삭제 |

## Enum 값
| Table | Column | Value | Meaning |
| --- | --- | --- | --- |

## 인증 관련 테이블
- users, roles, sessions, tokens, audit 관련 테이블이 있으면 문서화한다.
