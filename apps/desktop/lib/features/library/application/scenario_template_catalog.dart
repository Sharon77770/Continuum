import 'package:game_core/game_core.dart';

/// A ready-to-play scenario that can be copied into a new editable World.
class ScenarioTemplate {
  const ScenarioTemplate({
    required this.id,
    required this.name,
    required this.tagline,
    required this.description,
    required this.genre,
    required this.tone,
    required this.rules,
    required this.playerName,
    required this.playerDescription,
    required this.playerBackground,
    required this.playerTraits,
    required this.characterName,
    required this.characterRole,
    required this.characterDescription,
    required this.characterPersonality,
    required this.characterBackground,
    required this.characterPublicInformation,
    required this.characterSecretInformation,
    required this.locationName,
    required this.locationDescription,
    required this.openingSituation,
    required this.loreTitle,
    required this.loreCategory,
    required this.loreContent,
  });

  final String id;
  final String name;
  final String tagline;
  final String description;
  final List<String> genre;
  final List<String> tone;
  final List<String> rules;
  final String playerName;
  final String playerDescription;
  final String playerBackground;
  final List<String> playerTraits;
  final String characterName;
  final String characterRole;
  final String characterDescription;
  final String characterPersonality;
  final String characterBackground;
  final String characterPublicInformation;
  final String characterSecretInformation;
  final String locationName;
  final String locationDescription;
  final String openingSituation;
  final String loreTitle;
  final String loreCategory;
  final String loreContent;

  World createWorld({
    String? nameOverride,
    String? descriptionOverride,
    List<String>? genreOverride,
    List<String>? toneOverride,
  }) {
    final DateTime now = DateTime.now().toUtc();
    final String worldId = createStableId('world');
    final String characterId = createStableId('char');
    final String locationId = createStableId('loc');
    return World(
      id: worldId,
      name:
          nameOverride?.trim().isNotEmpty == true ? nameOverride!.trim() : name,
      description: descriptionOverride ?? description,
      genre: genreOverride ?? genre,
      tone: toneOverride ?? tone,
      rules: rules,
      playerDefinition: PlayerDefinition(
        name: playerName,
        description: playerDescription,
        background: playerBackground,
        traits: playerTraits,
      ),
      openingDefinition: OpeningDefinition(
        startingLocationId: locationId,
        startingCharacterIds: [characterId],
        situation: openingSituation,
      ),
      characters: [
        StoryCharacter(
          id: characterId,
          worldId: worldId,
          name: characterName,
          role: characterRole,
          description: characterDescription,
          personality: characterPersonality,
          background: characterBackground,
          publicInformation: characterPublicInformation,
          secretInformation: characterSecretInformation,
        ),
      ],
      locations: [
        StoryLocation(
          id: locationId,
          worldId: worldId,
          name: locationName,
          description: locationDescription,
        ),
      ],
      loreEntries: [
        LoreEntry(
          id: createStableId('lore'),
          worldId: worldId,
          title: loreTitle,
          category: loreCategory,
          content: loreContent,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
  }
}

class ScenarioTemplateCatalog {
  static const List<ScenarioTemplate> templates = [
    ScenarioTemplate(
      id: 'last_lighthouse',
      name: '마지막 등대의 불빛',
      tagline: '폭풍우 속 등대에 찾아온 세 번의 신호',
      description: '폭풍이 몰아치는 밤, 꺼진 등대와 바다에서 돌아온 낯선 불빛의 미스터리.',
      genre: ['미스터리', '판타지'],
      tone: ['따뜻함', '잔잔한 긴장감'],
      rules: ['등대의 불빛은 바다에서 길을 잃은 사람에게만 보인다.', '인물의 선택과 대화로 미스터리를 조금씩 밝혀 간다.'],
      playerName: '지우',
      playerDescription: '폭풍을 피해 등대에 도착한 여행자.',
      playerBackground: '바닷가 마을에서 자랐지만 오래전부터 고향을 떠나 여행했다.',
      playerTraits: ['호기심이 많다', '침착하다'],
      characterName: '하린',
      characterRole: '등대지기',
      characterDescription: '오래된 등대와 바다의 변화를 누구보다 잘 안다.',
      characterPersonality: '신중하고 다정하지만 중요한 이야기는 쉽게 꺼내지 않는다.',
      characterBackground: '이 등대를 지켜 온 가족의 마지막 사람이다.',
      characterPublicInformation: '폭풍이 오기 전 등대의 불을 껐다.',
      characterSecretInformation: '오늘 밤 바다에서 실종된 동생의 신호를 보았다.',
      locationName: '폭풍 등대',
      locationDescription: '절벽 끝에 선 오래된 등대. 현관에는 빗물이 고이고 위층에서 희미한 빛이 샌다.',
      openingSituation: '한밤중 폭풍을 피해 등대 문을 두드린다. 꼭대기에서 꺼져 있어야 할 불빛이 세 번 깜박인다.',
      loreTitle: '바다의 세 신호',
      loreCategory: '전설',
      loreContent: '등대의 빛이 세 번 깜박이면 바다가 누군가를 돌려보내려 한다고 마을 사람들은 말한다.',
    ),
    ScenarioTemplate(
      id: 'midnight_archive',
      name: '자정의 기억 보관소',
      tagline: '사라진 기억을 맡기는 도시의 야간 기록관',
      description: '기억을 사고파는 근미래 도시. 야간 기록관인 당신에게 존재하지 않는 의뢰인의 기억이 도착한다.',
      genre: ['SF', '미스터리'],
      tone: ['차분함', '긴장감'],
      rules: [
        '기억은 기록하고 편집할 수 있지만 원본의 감정까지 지울 수는 없다.',
        '보관소의 모든 의뢰에는 기억을 맡긴 이유가 있다.'
      ],
      playerName: '서윤',
      playerDescription: '시청 산하 기억 보관소의 야간 기록관.',
      playerBackground: '기억 복원 전문가였지만 한 사건 이후 야간 근무만 맡고 있다.',
      playerTraits: ['관찰력이 좋다', '쉽게 믿지 않는다'],
      characterName: '도윤',
      characterRole: '기억 복원사',
      characterDescription: '깨진 기억 조각을 이어 붙이는 솜씨가 뛰어난 동료.',
      characterPersonality: '말수가 적고 농담을 자주 하지만 핵심은 피하지 않는다.',
      characterBackground: '도시 외곽에서 불법 기억 거래를 추적해 왔다.',
      characterPublicInformation: '정식 접수 절차를 거치지 않은 기억은 열람할 수 없다고 주장한다.',
      characterSecretInformation: '이번 기억 속 목소리를 이미 알고 있다.',
      locationName: '기억 보관소 야간실',
      locationDescription: '유리 보관함과 낮은 푸른 조명이 이어지는 지하 기록실.',
      openingSituation: '자정이 되자 비어 있던 보관함 하나가 저절로 열리고, 당신의 목소리로 된 기억 파일이 도착한다.',
      loreTitle: '기억 열람 규정',
      loreCategory: '도시 규정',
      loreContent: '시민은 본인의 기억에 한해 열람을 허가할 수 있다. 타인의 기억을 무단으로 재생하면 범죄로 취급된다.',
    ),
    ScenarioTemplate(
      id: 'ember_guild',
      name: '잿빛 왕국의 길드',
      tagline: '용의 재가 내리는 변방에서 시작하는 모험',
      description: '마법 왕국의 변방 길드에 새로 도착한 모험가. 사라진 마을과 오래된 봉인의 흔적을 조사한다.',
      genre: ['판타지', '모험'],
      tone: ['희망적', '장엄함'],
      rules: ['마법은 대가와 흔적을 남긴다.', '길드 의뢰는 지역 사람들의 삶과 연결되어 있다.'],
      playerName: '아린',
      playerDescription: '변방 길드에 막 등록한 떠돌이 모험가.',
      playerBackground: '고향을 떠나 자신만의 이름으로 첫 의뢰를 찾고 있다.',
      playerTraits: ['대담하다', '약속을 지킨다'],
      characterName: '베른',
      characterRole: '길드 접수원',
      characterDescription: '의뢰와 지역 사정에 밝은 veteran 길드원.',
      characterPersonality: '무뚝뚝하지만 초보 모험가를 지나치지 못한다.',
      characterBackground: '한때 유명한 모험단의 방패였으나 마지막 원정 이후 길드에 남았다.',
      characterPublicInformation: '북쪽 숲길에서 마을 사람들의 실종 신고가 이어지고 있다.',
      characterSecretInformation: '실종자 중 한 명이 옛 원정의 생존자다.',
      locationName: '재의 문장 길드',
      locationDescription: '모닥불과 의뢰 게시판이 있는 돌벽의 길드 회관.',
      openingSituation:
          '베른이 봉인된 낡은 의뢰서를 내민다. 잿빛 비가 내린 뒤 북쪽 마을 전체가 사라졌다고 적혀 있다.',
      loreTitle: '용의 재',
      loreCategory: '전승',
      loreContent: '백 년 전 잠든 용의 숨결이 닿은 땅에는 재가 내리고, 그 재는 마법의 흔적을 오래 간직한다.',
    ),
    ScenarioTemplate(
      id: 'orion_signal',
      name: '오리온호의 마지막 교신',
      tagline: '귀환 항로에서 끊긴 구조 신호',
      description: '먼 행성에서 귀환하던 탐사선 오리온호. 항로 한가운데서 오래전에 실종된 구조선의 신호가 잡힌다.',
      genre: ['SF', '생존'],
      tone: ['긴장감', '희망적'],
      rules: [
        '선내 자원은 한정되어 있어 선택마다 우선순위가 필요하다.',
        '자동 시스템은 명령을 따르지만 의도를 추측하지 않는다.'
      ],
      playerName: '민서',
      playerDescription: '오리온호의 임무 책임자.',
      playerBackground: '첫 장거리 귀환 임무를 맡았으며 승무원 모두의 안전을 책임진다.',
      playerTraits: ['결단력 있다', '팀을 먼저 생각한다'],
      characterName: '이안',
      characterRole: '항법사',
      characterDescription: '신호의 위치와 귀환 항로를 동시에 계산하는 항법 담당자.',
      characterPersonality: '침착하고 현실적이지만 위험 앞에서 동료를 포기하지 않는다.',
      characterBackground: '실종된 구조선 탐사대의 가족이 있다.',
      characterPublicInformation: '신호는 폐기된 구조선 아르고의 호출 코드와 일치한다.',
      characterSecretInformation: '그 호출 코드에 개인용 암호가 섞여 있다는 것을 알아차렸다.',
      locationName: '오리온호 함교',
      locationDescription: '항법 화면과 비상 통신 콘솔이 켜진 소형 탐사선의 지휘 구역.',
      openingSituation:
          '귀환 점화 직전, 실종된 구조선의 구조 신호가 함교 전체에 울린다. 신호는 구조 요청과 함께 좌표를 전송한다.',
      loreTitle: '구조선 아르고',
      loreCategory: '임무 기록',
      loreContent:
          '아르고는 12년 전 외곽 위성 조사 중 실종되었다. 공식 기록에는 잔해도 생존자도 발견되지 않았다고 적혀 있다.',
    ),
  ];

  static ScenarioTemplate? find(String id) =>
      templates.where((ScenarioTemplate item) => item.id == id).firstOrNull;
}
