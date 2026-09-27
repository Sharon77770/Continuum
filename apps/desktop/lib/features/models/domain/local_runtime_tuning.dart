import 'model_catalog.dart';

/// CPU, context and prompt-batch limits applied to the managed local runtime.
class LocalRuntimeTuning {
  const LocalRuntimeTuning({
    required this.threads,
    required this.contextSize,
    required this.batchSize,
    required this.microBatchSize,
  });

  factory LocalRuntimeTuning.forProfile({
    required LocalResourceProfile profile,
    required int modelContextSize,
    int logicalProcessors = 1,
  }) {
    final int processors = logicalProcessors.clamp(1, 256).toInt();
    final int modelLimit = modelContextSize.clamp(2048, 8192).toInt();
    return switch (profile) {
      LocalResourceProfile.conservative => LocalRuntimeTuning(
          threads: (processors + 1) ~/ 2,
          contextSize: 2048,
          batchSize: 256,
          microBatchSize: 128,
        ),
      LocalResourceProfile.balanced => LocalRuntimeTuning(
          threads: (processors * 3 + 3) ~/ 4,
          contextSize: modelLimit < 4096 ? modelLimit : 4096,
          batchSize: 512,
          microBatchSize: 256,
        ),
      LocalResourceProfile.performance => LocalRuntimeTuning(
          threads: processors,
          contextSize: modelLimit,
          batchSize: 2048,
          microBatchSize: 512,
        ),
    };
  }

  final int threads;
  final int contextSize;
  final int batchSize;
  final int microBatchSize;
}
