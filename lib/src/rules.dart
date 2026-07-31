import 'package:organiza_downloads/src/config.dart';
import 'package:organiza_downloads/src/models.dart';

class RuleClassifier {
  RuleClassifier(this.config);

  final OrganizerConfig config;

  AnalysisResult classify(FileEntry entry) {
    final lowerName = entry.name.toLowerCase();
    final extension = entry.extension;

    if (entry.isFile && entry.sizeBytes == 0) {
      return AnalysisResult(
        entry: entry,
        action: FileAction.quarantine,
        category: 'temporarios',
        risk: RiskLevel.low,
        reason: 'arquivo vazio',
      );
    }

    if (lowerName.startsWith('.~lock') || lowerName.endsWith('#')) {
      return AnalysisResult(
        entry: entry,
        action: FileAction.quarantine,
        category: 'temporarios',
        risk: RiskLevel.low,
        reason: 'lock temporario de editor',
      );
    }

    if (config.importantKeywords.any(lowerName.contains)) {
      return AnalysisResult(
        entry: entry,
        action: FileAction.keep,
        category: _importantCategory(lowerName),
        risk: RiskLevel.high,
        reason: 'nome sugere documento importante',
      );
    }

    if (entry.isDirectory) {
      return AnalysisResult(
        entry: entry,
        action: FileAction.review,
        category: 'outros',
        risk: RiskLevel.medium,
        reason: 'pasta direta precisa de revisao manual',
      );
    }

    if (config.installerExtensions.contains(extension)) {
      return AnalysisResult(
        entry: entry,
        action: FileAction.quarantine,
        category: 'instaladores',
        risk: RiskLevel.medium,
        reason: 'instalador geralmente pode ir para triagem apos uso',
      );
    }

    if (_isTemporaryExtension(extension) ||
        config.quarantineKeywords.any(lowerName.contains)) {
      return AnalysisResult(
        entry: entry,
        action: FileAction.quarantine,
        category: 'temporarios',
        risk: RiskLevel.low,
        reason: 'temporario ou cache provavel',
      );
    }

    if (config.model3dExtensions.contains(extension)) {
      return AnalysisResult(
        entry: entry,
        action: FileAction.review,
        category: 'modelos_3d',
        risk: RiskLevel.medium,
        reason: 'modelo 3D precisa de revisao manual',
      );
    }

    if (config.documentExtensions.contains(extension)) {
      return AnalysisResult(
        entry: entry,
        action: FileAction.review,
        category: 'documentos',
        risk: RiskLevel.high,
        reason: 'documento sem palavra-chave conclusiva',
      );
    }

    if (config.imageExtensions.contains(extension)) {
      return AnalysisResult(
        entry: entry,
        action: FileAction.review,
        category: 'imagens',
        risk: RiskLevel.medium,
        reason: 'imagem precisa de revisao manual',
      );
    }

    if (config.videoAudioExtensions.contains(extension)) {
      return AnalysisResult(
        entry: entry,
        action: FileAction.review,
        category: 'videos_audio',
        risk: RiskLevel.medium,
        reason: 'audio ou video precisa de revisao manual',
      );
    }

    if (config.backupExtensions.contains(extension)) {
      return AnalysisResult(
        entry: entry,
        action: FileAction.review,
        category: 'backups',
        risk: RiskLevel.medium,
        reason: 'arquivo compactado ou backup precisa de revisao manual',
      );
    }

    if (config.codeExtensions.contains(extension)) {
      return AnalysisResult(
        entry: entry,
        action: FileAction.review,
        category: 'codigo',
        risk: RiskLevel.medium,
        reason: 'arquivo tecnico precisa de revisao manual',
      );
    }

    return AnalysisResult(
      entry: entry,
      action: FileAction.review,
      category: 'outros',
      risk: RiskLevel.medium,
      reason: 'tipo nao mapeado',
    );
  }

  bool _isTemporaryExtension(String extension) {
    if (config.temporaryExtensions.contains(extension)) {
      return true;
    }
    return config.temporaryExtensions.any((item) => extension.endsWith(item));
  }

  String _importantCategory(String lowerName) {
    if (_containsAny(lowerName, const [
      'exame',
      'amil',
      'saude',
      'saúde',
    ])) {
      return 'saude';
    }
    if (_containsAny(lowerName, const [
      'irpf',
      'boleto',
      'fatura',
      'comprovante',
      'contracheque',
      'nota fiscal',
      'dctf',
      'das',
      'imposto',
      'cnpj',
    ])) {
      return 'financeiro_fiscal';
    }
    return 'documentos';
  }

  bool _containsAny(String value, List<String> needles) {
    return needles.any(value.contains);
  }
}
