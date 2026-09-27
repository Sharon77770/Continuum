# Local AI Novel Engine — Product Requirements Document

> Working Title: **Project Chronicle**
> Status: MVP / Draft
> Platform: Desktop
> Framework: Flutter + Dart
> Primary Mode: Single-player Visual Novel
> AI Runtime: User-provided Local LLM

---

## 1. Product Overview

Project Chronicle은 사용자가 직접 만든 세계관과 캐릭터를 기반으로 로컬 LLM이 이야기를 진행하는 **UGC 기반 AI Novel Engine**이다.

사용자는 정해진 게임 시나리오를 소비하는 대신 다음 요소를 직접 정의한다.

* 세계관
* 플레이어 캐릭터
* 등장인물
* 장소
* 기본 설정
* 이야기의 시작 상황

게임이 시작되면 Local LLM이 현재 세계 상태와 캐릭터 설정을 참고하여 NPC의 대사, 장면 묘사, 사건 및 선택지를 생성한다.

MVP에서는 **Visual Novel 형태의 Single Player 경험**에 집중한다.

향후 TRPG, Turn-based RPG 등의 Game System과 Multiplayer Host 기능을 추가할 수 있도록 데이터 모델과 Game Core는 UI에서 분리한다.

---

# 2. Product Vision

기존 AI Character Chat은 주로 다음 구조를 가진다.

```text
Character
    ↓
Conversation
    ↓
Character
    ↓
Conversation
```

Chronicle은 이를 **World 중심 구조**로 확장한다.

```text
World
├── Characters
├── Locations
├── Lore
├── Relationships
├── Events
└── Player

        ↓

    Game State

        ↓

    Local LLM

        ↓

Narrative / Dialogue / Choice

        ↓

    State Update
```

핵심은 AI와 대화하는 것이 아니라,

> **AI에 의해 움직이는 세계 안에서 플레이한다.**

는 경험을 제공하는 것이다.

---

# 3. Product Principles

## 3.1 Local First

게임 데이터와 세이브 데이터는 기본적으로 사용자의 PC에 저장한다.

LLM 또한 사용자가 직접 제공하는 Local LLM endpoint를 사용한다.

MVP에서는 다음 형태의 API를 우선 지원한다.

```text
OpenAI-compatible API
```

예:

```text
http://localhost:11434
http://localhost:8000/v1
```

특정 LLM runtime에 Game Core가 종속되어서는 안 된다.

---

## 3.2 World First

캐릭터 한 명과 대화하는 구조보다 **세계 전체의 상태**를 우선한다.

세계에는 여러 캐릭터와 장소가 존재할 수 있으며 각각 독립적인 상태를 가진다.

예:

```text
World

Location
 ├─ Laboratory
 ├─ Rooftop
 └─ Underground Facility

Characters
 ├─ Seo Yoon
 ├─ Ji Hyun
 └─ Player
```

현재 Scene은 World의 일부일 뿐이다.

---

## 3.3 AI Does Not Own the State

LLM은 Game State를 직접 변경할 수 없다.

LLM은 다음 상태 변경을 **제안**한다.

```text
Narrative Result

dialogue:
  "방금 그거... 너도 할 수 있었어?"

stateChanges:
  - relationship.suspicion +5

events:
  - PLAYER_POWER_DISCOVERED
```

Game Core가 이를 검증한 뒤 실제 World State에 적용한다.

즉:

```text
LLM
 ↓
Structured Result
 ↓
Game Core Validation
 ↓
World State
```

구조를 유지한다.

---

# 4. Target Experience

사용자가 앱을 처음 실행한다.

```text
Chronicle

Your Worlds

[ Seoul 2043 ]

Last played
Chapter 3 · 2h 14m

[ Continue ]

────────────────

+ Create World
```

새로운 세계를 만든다.

```text
World Name
Seoul 2043

Description
2043년 서울.
거대 기업들이 도시를 분할 통치하고 있으며
일부 인간에게 초능력이 발생하기 시작했다.

Genre
Modern / SF

Tone
Dark / Serious

[ Continue ]
```

플레이어 캐릭터를 생성한다.

```text
Name
Minjae

Description
대기업에서 탈출한 전직 보안 엔지니어.

Traits

+ Security Expert
+ Suspicious
+ Poor Fighter
```

NPC를 생성한다.

```text
Name
Seo Yoon

Role
Graduate Researcher

Personality
냉정하지만 호기심이 많다.

Secret
초능력자 관리기관 소속이다.
```

시작 상황을 정의한다.

```text
새벽 연구실.

서버를 고치던 플레이어가
실수로 시간을 멈추는 능력을 사용했고
서윤이 그것을 목격했다.
```

게임을 시작한다.

---

# 5. Core User Flow

```text
Application Start

      ↓

Library

      ↓

Create World
      │
      ├─ World
      ├─ Player
      ├─ Characters
      └─ Opening

      ↓

Play

      ↓

Scene

      ↓

Player Choice / Free Input

      ↓

Game Core

      ↓

LLM

      ↓

Narrative Result

      ↓

State Update

      ↓

Next Scene
```

---

# 6. Application Structure

앱은 크게 세 개의 공간으로 구성한다.

## 6.1 Library

생성하거나 가져온 World를 관리한다.

주요 기능:

* World 생성
* World 삭제
* World 복제
* World Import
* World Export
* 최근 플레이
* Continue
* New Game

World는 게임 콘텐츠이고 Save는 플레이 기록이다.

따라서 하나의 World에서 여러 Save를 생성할 수 있어야 한다.

```text
World
 ├─ Save 1
 ├─ Save 2
 └─ Save 3
```

---

# 7. World Studio

World를 제작하고 수정하는 공간이다.

MVP 메뉴:

```text
WORLD

Overview
Lore
Characters
Locations

GAME

Player
Opening
Novel Settings

ASSETS

Portraits
Backgrounds
```

---

# 8. World Definition

World는 다음 정보를 가진다.

```text
World

id
name
description
genre[]
tone[]
rules[]
lore[]
characters[]
locations[]
assets
metadata
```

예:

```json
{
  "name": "Seoul 2043",
  "genre": ["modern", "sf"],
  "tone": ["dark"],
  "description": "2043년 서울...",
  "rules": [
    "마법은 존재하지 않는다.",
    "일부 인간에게 초능력이 존재한다.",
    "일반인은 초능력자의 존재를 모른다."
  ]
}
```

---

# 9. Lore

World의 고정 설정을 저장한다.

Lore는 단순한 하나의 거대한 Prompt로 관리하지 않는다.

각 Lore Entry를 독립적으로 관리한다.

```text
Lore

Title
초능력자의 등장

Category
History

Content
2037년부터 원인을 알 수 없는...
```

Category 예:

```text
History
Society
Technology
Magic
Culture
Organization
Custom
```

MVP에서는 단순 CRUD와 LLM Context 제공만 구현한다.

---

# 10. Character

Character는 World에 존재하는 인물이다.

기본 구조:

```text
Character

id
name
description
appearance
personality
background
traits[]
secrets[]
relationships[]
portrait
```

NPC는 **공개 정보와 비밀 정보**를 구분할 수 있다.

예:

```text
Public

대학원생.
말수가 적고 냉정하다.


Secret

초능력자 관리기관 소속.
플레이어를 감시하고 있다.
```

Secret 정보는 Narrator 및 해당 Character context에는 제공할 수 있지만 플레이어에게 직접 노출하지 않는다.

---

# 11. Player Character

Player 역시 Character와 유사한 구조를 가진다.

```text
Player

name
description
background
traits[]
```

MVP Novel Mode에서는 복잡한 RPG Stats를 제공하지 않는다.

즉 다음은 MVP에서 제외한다.

```text
STR
DEX
INT
HP
MP
Level
EXP
```

향후 Game System에서 추가한다.

---

# 12. Location

World 내 장소를 정의한다.

```text
Location

id
name
description
parentLocation
background
```

계층 구조를 지원한다.

```text
Seoul
 ├─ Kookmin University
 │    ├─ Laboratory
 │    └─ Rooftop
 │
 └─ Underground Facility
```

MVP에서 실제 2D Map은 제공하지 않는다.

Location은 논리적인 Scene Context 역할을 한다.

---

# 13. Opening

게임 시작 상태를 정의한다.

```text
Starting Location

Laboratory


Starting Characters

Player
Seo Yoon


Opening Prompt

새벽 연구실.

플레이어가 서버를 고치던 중
시간을 멈추는 능력을 사용했고
서윤이 그것을 목격했다.
```

---

# 14. Novel Player

Novel Player가 실제 플레이 화면이다.

기본 구조:

```text
┌────────────────────────────────────────────┐
│ Seoul 2043                    Laboratory   │
│                                            │
│                                            │
│                 SCENE                      │
│                                            │
│                                            │
│ ┌────────────────────────────────────────┐ │
│ │ Seo Yoon                               │ │
│ │                                        │ │
│ │ "방금 그거..."                         │ │
│ │                                        │ │
│ │ "너도 할 수 있었어?"                  │ │
│ │                                        │ │
│ │  > 무슨 말인지 모르겠는데.            │ │
│ │  > 너도?                              │ │
│ │  > 침묵한다.                          │ │
│ │                                        │ │
│ │  직접 행동 입력...                    │ │
│ └────────────────────────────────────────┘ │
│                                            │
│ [Characters] [History] [World] [Menu]     │
└────────────────────────────────────────────┘
```

---

# 15. Player Interaction

Novel Mode는 두 가지 입력 방식을 동시에 지원한다.

## Generated Choices

LLM이 상황에 맞는 선택지를 생성한다.

예:

```text
1. 무슨 말인지 모르겠는데.
2. 너도?
3. 침묵한다.
```

## Free Input

플레이어가 직접 행동이나 대사를 입력할 수 있다.

예:

```text
일단 모르는 척하면서 서버 로그를 다시 확인한다.
```

Generated Choice를 강제하지 않는다.

---

# 16. Narrative Response

LLM 응답은 일반 문자열이 아니라 Structured Output을 사용한다.

개념적 형태:

```json
{
  "scene": {
    "speaker": "seo_yoon",
    "dialogue": "너도 할 수 있었어?",
    "narration": "서윤이 조용히 문을 잠근다."
  },

  "choices": [
    "무슨 말인지 모르겠는데.",
    "너도?",
    "침묵한다."
  ],

  "stateChanges": [],

  "events": []
}
```

실제 schema는 구현 단계에서 versioning한다.

---

# 17. World State

Save마다 독립적인 World State를 가진다.

```text
WorldState

currentLocation
currentCharacters
relationships
flags
events
characterStates
gameTime
```

예:

```json
{
  "currentLocation": "laboratory",

  "relationships": {
    "seo_yoon": {
      "trust": 20,
      "suspicion": 45
    }
  },

  "flags": {
    "seo_yoon_knows_player_power": true
  }
}
```

World 원본 데이터와 World State를 반드시 분리한다.

---

# 18. Character Memory

NPC가 모든 대화를 Prompt에 계속 들고 있는 구조는 사용하지 않는다.

Character별 Memory를 관리한다.

```text
Character Memory

Short-term
최근 Scene / 대화

Long-term
중요 사건

Knowledge
해당 Character가 알고 있는 사실
```

예:

```text
Seo Yoon knows

✓ Player can stop time
✓ Agency exists
✕ Player stole company data
```

MVP에서는 완벽한 memory system보다 다음을 우선한다.

1. 최근 대화 유지
2. 중요한 Event 저장
3. Character Knowledge 분리

Embedding 기반 retrieval은 MVP 이후 검토한다.

---

# 19. Relationship

NPC와 Player 사이의 관계 상태를 지원한다.

기본적으로 시스템이 특정 관계 모델을 강제하지 않는다.

MVP 기본값:

```text
Trust
Affection
Suspicion
Hostility
```

World Creator가 일부 항목을 비활성화할 수 있다.

수치는 Player에게 직접 보여주지 않는 것을 기본 UX로 한다.

Studio / Debug Mode에서는 확인 가능하다.

---

# 20. Game Time

World State에 Game Time을 유지한다.

```text
Day 3
02:13
```

시간은 Scene 진행 과정에서 변경될 수 있다.

이를 통해:

```text
Character availability
Location state
Event trigger
```

등을 향후 구현할 수 있다.

MVP에서는 시간 저장 및 LLM Context 반영까지만 지원한다.

---

# 21. Assets

MVP에서는 AI Image Generation을 구현하지 않는다.

사용자가 직접 이미지를 등록한다.

지원 대상:

```text
Character Portrait
Background
World Cover
```

지원 포맷:

```text
PNG
JPEG
WEBP
```

Asset은 World Pack 내부에서 관리한다.

---

# 22. Save System

Save에는 최소 다음 정보를 저장한다.

```text
World Version
World State
Conversation History
Character Memory
Current Scene
Game Time
```

지원 기능:

```text
Manual Save
Quick Save
Auto Save
Load
```

Auto Save는 Scene 진행 이후 수행한다.

---

# 23. Local LLM

## Provider Interface

Game Core가 특정 Runtime을 직접 참조하지 않는다.

```text
LlmProvider

generate()
stream()
healthCheck()
modelInfo()
```

MVP Provider:

```text
OpenAICompatibleProvider
```

지원해야 할 주요 기능:

* Streaming
* Structured Output
* Connection Test
* Configurable endpoint
* Configurable model
* Context limit 설정

---

# 24. LLM Context Builder

매 요청마다 전체 World를 무작정 Prompt에 넣지 않는다.

Context Builder가 현재 Scene에 필요한 정보를 구성한다.

```text
System Rules

Relevant World Lore

Current Location

Present Characters

Character Knowledge

Character Memory

World State

Recent Conversation

Player Input
```

MVP에서는 deterministic selection을 우선한다.

Embedding / RAG는 필요성이 확인된 후 도입한다.

---

# 25. LLM Failure Handling

Local Model은 JSON format을 완벽하게 지키지 않을 수 있다.

따라서 다음 단계가 필요하다.

```text
LLM Response

      ↓

Parse

      ↓

Schema Validation

 ┌────┴────┐
 │         │
Valid    Invalid
 │         │
 ↓         ↓
Apply    Repair
           │
           ↓
        Retry
```

Retry 횟수를 초과하면 게임을 종료하지 않고 사용자에게 재생성 기능을 제공한다.

---

# 26. Generation UX

Local LLM은 응답 속도가 느릴 수 있다.

따라서 생성 과정에서 UI가 멈춰 보이면 안 된다.

가능한 경우 narration/dialogue를 streaming하여 표시한다.

상태 표시:

```text
Seo Yoon is responding...
```

또는 세계 테마에 맞는 최소한의 loading indicator를 사용한다.

모델 내부 용어인:

```text
Inference
Tokens
Context
Prompt
```

등은 기본 Player UI에서 노출하지 않는다.

---

# 27. Novel Settings

World Creator가 Novel의 기본 플레이 방식을 설정한다.

MVP:

```text
Generated Choices
ON / OFF

Free Input
ON / OFF

Choice Count
2 - 5

Narration
Minimal / Normal / Detailed

Story Freedom
Guided / Balanced / Sandbox
```

단, 이는 Prompt만 바꾸는 옵션이 아니라 Context Builder 및 Game Core behavior에도 반영할 수 있도록 모델링한다.

---

# 28. Architecture

Repository 구조 초안:

```text
apps/

  desktop/
    Flutter Desktop Application


packages/

  game_core/
    World
    Character
    Scene
    State
    Event
    Save

  world_format/
    World serialization
    World Pack

  novel_system/
    Novel-specific rules
    Narrative processing

  llm_client/
    Provider
    Context Builder
    Structured Output

  persistence/
    Save
    SQLite
    Asset management

  game_protocol/
    Future multiplayer protocol
```

MVP에서는 `game_protocol`을 실제 사용하지 않아도 된다.

단, Game Core가 Flutter UI에 직접 의존해서는 안 된다.

---

# 29. State Flow

모든 플레이 행동은 Action으로 표현한다.

```text
Player
  ↓
PlayerAction
  ↓
NovelSystem
  ↓
ContextBuilder
  ↓
LLM
  ↓
NarrativeResult
  ↓
Validation
  ↓
GameEvent[]
  ↓
GameCore
  ↓
WorldState
  ↓
UI
```

UI에서 World State를 직접 변경하지 않는다.

이 구조는 향후 Multiplayer Server가 GameCore의 authority를 가져갈 수 있도록 하기 위함이다.

---

# 30. Persistence

MVP 권장:

```text
SQLite
```

DB에는 다음 데이터를 저장한다.

```text
World metadata
Save metadata
World State
Character Memory
Conversation
Events
```

이미지 등의 binary asset은 filesystem에 저장한다.

---

# 31. World Pack

World를 하나의 패키지로 Export할 수 있다.

예:

```text
seoul-2043.worldpack
```

내부 개념:

```text
manifest.json

world/
  world.json
  lore.json
  characters.json
  locations.json

assets/
  portraits/
  backgrounds/
  cover/

config/
  novel.json
```

MVP에서는 압축 파일 기반 format을 사용해도 된다.

Format에는 version을 반드시 포함한다.

```json
{
  "formatVersion": 1
}
```

---

# 32. Desktop Platform

MVP 우선 지원:

```text
Windows
```

Framework:

```text
Flutter Desktop
Dart
```

추후:

```text
Linux
macOS
```

를 고려한다.

플랫폼별 코드는 최소화한다.

---

# 33. MVP Scope

## MUST

* Flutter Desktop Application
* World Library
* World Creation
* World Editing
* Lore
* Character Creation
* Player Creation
* Location
* Opening Scenario
* Novel Player
* Generated Choices
* Free Input
* Local LLM connection
* Streaming response
* Structured Narrative Result
* World State
* Character Memory
* Relationship State
* Save / Load
* Portrait
* Background
* World Import / Export

## SHOULD

* Auto Save
* Quick Save
* World duplication
* Conversation history
* LLM response regeneration
* Debug World State viewer
* Theme accent per World

## NOT MVP

* Multiplayer
* Dedicated Server
* TRPG System
* Turn-based RPG
* Combat
* Stats / Level
* 2D map movement
* 3D
* Image Generation
* Voice
* Cloud inference service
* Account
* Community
* Workshop
* Mod marketplace
* Mobile
* Web version

---

# 34. Future Game Systems

Architecture는 다음 시스템을 추가할 수 있어야 한다.

```text
NovelSystem          ← MVP

TRPGSystem
TurnBasedRPGSystem
RoleplaySystem
MysterySystem
DatingSimSystem
SurvivalSystem
```

World와 Game System은 논리적으로 분리한다.

```text
World
      +
Game System
      =
Campaign
```

따라서 동일 World를 서로 다른 Game System에서 사용할 수 있는 구조를 목표로 한다.

---

# 35. Future Multiplayer

MVP에서는 구현하지 않는다.

향후 구조는 **Host-authoritative multiplayer**를 목표로 한다.

```text
HOST

Flutter Client
     │
Game Server
     │
Game Core
     │
Local LLM
     │
World Save

       │
       ├──────── Client
       ├──────── Client
       └──────── Client
```

호스트가 다음을 담당한다.

* World Authority
* LLM Inference
* Save
* NPC State
* Rule Processing

클라이언트는 Action을 서버에 전달하고 결과 State/Event를 수신한다.

호스트 종료 시 Session도 종료되는 것을 기본 동작으로 한다.

Host Migration은 초기 Multiplayer Scope에 포함하지 않는다.

---

# 36. UX Direction

앱의 UX는 세 영역으로 분리한다.

```text
Library
   ↓
Studio
   ↓
Player
```

### Library

작품을 고르는 공간.

게임 런처보다는 개인 작품 라이브러리에 가까운 디자인.

### Studio

World를 제작하는 공간.

Editor이지만 IDE처럼 보이지 않아야 한다.

세계관 백과사전 / 창작 도구에 가까운 UI를 사용한다.

### Player

몰입이 최우선.

Editor UI를 최대한 숨긴다.

배경과 Character가 화면의 대부분을 차지하고 Dialogue UI를 하단에 배치한다.

---

# 37. Visual Direction

기본:

```text
Dark
Cinematic
Minimal
Editorial
```

피해야 할 것:

* AI SaaS 스타일
* 과도한 Rounded Card
* Purple Gradient
* Neon Cyberpunk
* Dashboard 형태
* IDE 형태
* ChatGPT 형태

AI는 제품의 기능이지 디자인 언어가 아니다.

---

# 38. Theme System

World가 일부 Player Theme을 정의할 수 있다.

예:

```json
{
  "theme": {
    "accent": "#9A7B4F",
    "dialogueStyle": "cinematic",
    "fontStyle": "serif"
  }
}
```

앱의 전체 UX 구조는 유지하되 World마다 분위기를 다르게 표현할 수 있도록 한다.

---

# 39. MVP Success Criteria

MVP는 다음 시나리오가 처음부터 끝까지 동작하면 성공으로 판단한다.

1. 앱을 설치한다.
2. Local LLM endpoint를 연결한다.
3. 새로운 World를 생성한다.
4. 세계관을 작성한다.
5. Player를 생성한다.
6. NPC 2명 이상을 생성한다.
7. Location을 생성한다.
8. Opening Scenario를 작성한다.
9. 게임을 시작한다.
10. NPC와 상호작용한다.
11. 선택지를 사용한다.
12. 자유 입력으로 행동한다.
13. World State가 변화한다.
14. NPC가 이전 사건을 기억한다.
15. 게임을 저장한다.
16. 앱을 종료한다.
17. 다시 실행한다.
18. Save를 불러온다.
19. 이전 상태에서 자연스럽게 게임을 계속한다.

이 전체 과정에서 사용자는 직접 Prompt Engineering을 할 필요가 없어야 한다.

---

# 40. MVP Non-Goal

MVP의 목표는 완성된 범용 게임 엔진을 만드는 것이 아니다.

MVP에서 검증할 것은 다음 세 가지다.

### 1. World

사용자가 자신만의 세계와 Character를 쉽게 만들 수 있는가.

### 2. Persistence

LLM과 장시간 상호작용하면서도 세계와 Character가 일관성을 유지할 수 있는가.

### 3. Play

AI Chat이 아니라 실제 Visual Novel을 플레이하고 있다는 경험을 줄 수 있는가.

이 세 가지가 검증된 이후에만 Multiplayer 및 추가 Game System을 개발한다.

---

# 41. Product Definition

Project Chronicle은 AI Character Chat 애플리케이션이 아니다.

또한 LLM이 모든 것을 결정하는 AI Game도 아니다.

**사용자가 세계를 만들고, Game Engine이 그 세계의 상태를 유지하며, Local LLM이 그 안의 인물과 이야기를 살아 움직이게 만드는 Local-first UGC Story Game Engine이다.**
