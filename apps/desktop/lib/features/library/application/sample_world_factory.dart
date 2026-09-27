import 'package:game_core/game_core.dart';

/// A compact, immediately playable scenario used to exercise New Game.
class SampleWorldFactory {
  static World create() {
    final DateTime now = DateTime.now().toUtc();
    const String worldId = 'sample_last_lighthouse';
    const String locationId = 'sample_storm_lighthouse';
    const String characterId = 'sample_keeper_harin';
    return World(
      id: worldId,
      name: '마지막 등대의 불빛',
      description: '폭풍우가 몰아치는 밤, 꺼진 등대와 바다에서 돌아온 낯선 불빛의 미스터리.',
      genre: const ['미스터리', '판타지'],
      tone: const ['따뜻함', '잔잔한 긴장감'],
      rules: const [
        '등대의 불빛은 바다에서 길을 잃은 사람에게만 보인다.',
        '이야기는 인물의 선택과 대화로 미스터리를 조금씩 밝혀 간다.',
      ],
      playerDefinition: const PlayerDefinition(
        name: '지우',
        description: '폭풍을 피해 등대에 도착한 여행자.',
        background: '바닷가 마을에서 자랐지만 오래전부터 고향을 떠나 여행했다.',
        traits: ['호기심이 많다', '침착하다'],
      ),
      openingDefinition: const OpeningDefinition(
        startingLocationId: locationId,
        startingCharacterIds: [characterId],
        situation: '한밤중 폭풍을 피해 등대 문을 두드린다. 꼭대기에서 꺼져 있어야 할 불빛이 세 번 깜박인다.',
      ),
      characters: const [
        StoryCharacter(
          id: characterId,
          worldId: worldId,
          name: '하린',
          role: '등대지기',
          description: '오래된 등대와 바다의 변화를 누구보다 잘 안다.',
          appearance: '젖은 짙은 남색 외투와 손에 든 황동 랜턴.',
          personality: '신중하고 다정하지만 중요한 이야기는 쉽게 꺼내지 않는다.',
          background: '이 등대를 지켜 온 가족의 마지막 사람이다.',
          publicInformation: '폭풍이 오기 전 등대의 불을 껐다.',
          secretInformation: '오늘 밤 바다에서 실종된 동생의 신호를 보았다.',
        ),
      ],
      locations: const [
        StoryLocation(
          id: locationId,
          worldId: worldId,
          name: '폭풍 등대',
          description: '절벽 끝에 선 오래된 등대. 1층 현관에는 빗물이 고이고 위층에서 희미한 빛이 샌다.',
        ),
      ],
      loreEntries: const [
        LoreEntry(
          id: 'sample_lantern_lore',
          worldId: worldId,
          title: '바다의 세 신호',
          category: '전설',
          content: '마을 사람들은 등대의 빛이 세 번 깜박이면 바다가 누군가를 돌려보내려 한다고 말한다.',
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
  }
}
