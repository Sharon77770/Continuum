import 'package:game_core/game_core.dart';

/// Storage contract for independent playthroughs associated with a World.
abstract interface class CampaignRepository {
  Future<List<Campaign>> listCampaigns(String worldId);
  Future<Campaign?> getCampaign(String campaignId);
  Future<void> saveCampaign(Campaign campaign);
}
