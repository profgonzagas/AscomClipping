import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const PCDFClippingApp());
}

// ========== MODELOS ==========
enum NewsCategory { pcdf, policia, seguranca, justica, geral }
enum NewsType { jornal, portal, social, agencia, video }

class NewsArticle {
  final String id;
  final String title;
  final String source;
  final String url;
  final String content;
  final DateTime date;
  final NewsCategory category;
  final int relevanceScore;
  final int engagement;
  final NewsType type;
  final String? preview;
  final bool isRead;

  NewsArticle({
    required this.id,
    required this.title,
    required this.source,
    required this.url,
    required this.content,
    required this.date,
    required this.category,
    required this.relevanceScore,
    required this.engagement,
    required this.type,
    this.preview,
    this.isRead = false,
  });

  String get formattedDate => DateFormat('dd/MM/yyyy').format(date);
  String get formattedTime => DateFormat('HH:mm').format(date);

  String get engagementFormatted {
    if (engagement > 1000) return '${(engagement / 1000).toStringAsFixed(1)}k';
    return engagement.toString();
  }

  String get relevanceText {
    if (relevanceScore >= 8) return 'Alta Relevância';
    if (relevanceScore >= 5) return 'Média Relevância';
    return 'Baixa Relevância';
  }
}

// ========== SERVIÇO DE BUSCA DE NOTÍCIAS ==========
class NewsSearchService {
  static final List<Map<String, dynamic>> _newsSources = [
    {
      'name': 'G1 Distrito Federal',
      'domain': 'g1.globo.com',
      'type': NewsType.portal,
      'weight': 10
    },
    {
      'name': 'Correio Braziliense',
      'domain': 'correiobraziliense.com.br',
      'type': NewsType.jornal,
      'weight': 9
    },
    {
      'name': 'UOL Notícias',
      'domain': 'noticias.uol.com.br',
      'type': NewsType.portal,
      'weight': 9
    },
    {
      'name': 'Terra Notícias',
      'domain': 'terra.com.br',
      'type': NewsType.portal,
      'weight': 8
    },
    {
      'name': 'CNN Brasil',
      'domain': 'cnnbrasil.com.br',
      'type': NewsType.portal,
      'weight': 9
    },
    {
      'name': 'Estadão',
      'domain': 'estadao.com.br',
      'type': NewsType.jornal,
      'weight': 9
    },
    {
      'name': 'O Globo',
      'domain': 'oglobo.globo.com',
      'type': NewsType.jornal,
      'weight': 9
    },
    {
      'name': 'Folha de S. Paulo',
      'domain': 'folha.uol.com.br',
      'type': NewsType.jornal,
      'weight': 9
    },
    {
      'name': 'R7 Notícias',
      'domain': 'noticias.r7.com',
      'type': NewsType.portal,
      'weight': 8
    },
    {
      'name': 'Jornal do Brasil',
      'domain': 'jb.com.br',
      'type': NewsType.jornal,
      'weight': 8
    },
    {
      'name': 'Metrópoles DF',
      'domain': 'metropoles.com',
      'type': NewsType.portal,
      'weight': 8
    },
    {
      'name': 'Agência Brasil',
      'domain': 'agenciabrasil.ebc.com.br',
      'type': NewsType.agencia,
      'weight': 7
    },
  ];

  static final List<Map<String, dynamic>> _newsTemplates = [
    {
      'title': 'PCDF prende quadrilha especializada em crimes cibernéticos no DF',
      'keywords': ['pcdf', 'prende', 'quadrilha', 'crimes cibernéticos', 'DF'],
      'baseScore': 9,
    },
    {
      'title': 'Operação da PCDF apreende 500kg de drogas no Paranoá',
      'keywords': ['operação', 'pcdf', 'apreende', 'drogas', 'paranoá'],
      'baseScore': 10,
    },
    {
      'title': 'PCDF inaugura nova delegacia especializada em Samambaia',
      'keywords': ['pcdf', 'inaugura', 'delegacia', 'samambaia'],
      'baseScore': 8,
    },
    {
      'title': 'Delegados da PCDF participam de curso internacional de investigação',
      'keywords': ['delegados', 'pcdf', 'curso', 'investigação'],
      'baseScore': 7,
    },
    {
      'title': 'PCDF desarticula esquema de roubo de cargas em rodovias do DF',
      'keywords': ['pcdf', 'desarticula', 'roubo', 'cargas', 'rodovias'],
      'baseScore': 9,
    },
    {
      'title': 'Polícia Civil do DF prende suspeitos de homicídio em Ceilândia',
      'keywords': ['polícia civil', 'df', 'prende', 'homicídio', 'ceilândia'],
      'baseScore': 8,
    },
    {
      'title': 'PCDF apreende armas e munições em operação no Itapoã',
      'keywords': ['pcdf', 'apreende', 'armas', 'munições', 'itapoã'],
      'baseScore': 9,
    },
    {
      'title': 'Delegacia da PCDF investiga fraudes em licitações no governo',
      'keywords': ['delegacia', 'pcdf', 'investiga', 'fraudes', 'licitações'],
      'baseScore': 9,
    },
  ];

  static List<NewsArticle> searchNews({int count = 10, DateTime? startDate, DateTime? endDate}) {
    final results = <NewsArticle>[];
    final now = DateTime.now();
    final random = DateTime.now().millisecondsSinceEpoch;

    // Filtro de data
    final effectiveStartDate = startDate ?? now.subtract(const Duration(days: 7));
    final effectiveEndDate = endDate ?? now;

    for (int i = 0; i < count; i++) {
      final template = _newsTemplates[i % _newsTemplates.length];
      final source = _newsSources[i % _newsSources.length];

      // Gerar data aleatória dentro do período
      final daysRange = effectiveEndDate.difference(effectiveStartDate).inDays;
      final randomDays = (random + i) % (daysRange + 1);
      final articleDate = effectiveStartDate.add(Duration(days: randomDays));

      // Gerar URL específica baseada no título e fonte
      final titleSlug = _generateSlug(template['title']);
      final url = 'https://${source['domain']}/noticias/${DateFormat('yyyy/MM').format(articleDate)}/$titleSlug';

      results.add(NewsArticle(
        id: '${now.millisecondsSinceEpoch}_$i',
        title: template['title'] as String,
        source: source['name'] as String,
        url: url,
        content: _generateContent(template['title'] as String, source['name'] as String),
        date: articleDate,
        category: NewsCategory.pcdf,
        relevanceScore: (template['baseScore'] as int) + (i % 3), // Variação pequena
        engagement: 1000 + (i * 237), // Engajamento variado
        type: source['type'] as NewsType,
        preview: _generatePreview(template['title'] as String),
      ));
    }

    // Ordenar por data mais recente
    results.sort((a, b) => b.date.compareTo(a.date));

    return results;
  }

  static String _generateSlug(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  static String _generateContent(String title, String source) {
    return 'A Polícia Civil do Distrito Federal (PCDF) realizou uma operação que resultou em significativas apreensões e prisões. "$title". A ação contou com o trabalho conjunto de várias delegacias especializadas e representa mais um avanço no combate ao crime organizado na região. A operação foi destacada pela $source como um marco nas investigações policiais do DF.';
  }

  static String _generatePreview(String title) {
    final previews = [
      'Operação da PCDF resulta em importantes apreensões...',
      'A Polícia Civil do DF avança nas investigações...',
      'Novo caso investigado pela PCDF mostra resultados...',
      'Ação policial no Distrito Federal tem balanço positivo...'
    ];
    return previews[title.length % previews.length];
  }
}

// ========== WIDGETS ==========
class NewsItemWidget extends StatelessWidget {
  final NewsArticle article;
  final VoidCallback? onTap;

  const NewsItemWidget({
    Key? key,
    required this.article,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      elevation: 3,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabeçalho com fonte e data
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getSourceColor(article.source),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      article.source,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        article.formattedDate,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        article.formattedTime,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Título
              Text(
                article.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                  height: 1.3,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // Preview do conteúdo
              if (article.preview != null) ...[
                Text(
                  article.preview!,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
              ],

              // Rodapé com score e botão
              Row(
                children: [
                  // Score de relevância
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getScoreColor(article.relevanceScore),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.star,
                          size: 12,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${article.relevanceScore}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Engajamento
                  Row(
                    children: [
                      Icon(Icons.visibility, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        article.engagementFormatted,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),

                  // Tipo de mídia
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[400]!),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _getTypeText(article.type),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 10,
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Botão Ler Notícia
                  ElevatedButton.icon(
                    onPressed: () => _launchUrl(article.url, context),
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: const Text('Ler Notícia'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1a365d),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getSourceColor(String source) {
    final colors = {
      'G1 Distrito Federal': Colors.red[700]!,
      'Correio Braziliense': Colors.blue[700]!,
      'UOL Notícias': Colors.orange[700]!,
      'Terra Notícias': Colors.green[700]!,
      'CNN Brasil': Colors.red[600]!,
      'Estadão': Colors.blue[800]!,
      'O Globo': Colors.blue[600]!,
      'Folha de S. Paulo': Colors.orange[800]!,
      'R7 Notícias': Colors.purple[700]!,
      'Jornal do Brasil': Colors.blue[700]!,
      'Metrópoles DF': Colors.purple[600]!,
      'Agência Brasil': Colors.green[600]!,
    };
    return colors[source] ?? Colors.grey[700]!;
  }

  Color _getScoreColor(int score) {
    if (score >= 9) return Colors.green[700]!;
    if (score >= 7) return Colors.orange[700]!;
    return Colors.red[700]!;
  }

  String _getTypeText(NewsType type) {
    switch (type) {
      case NewsType.jornal: return 'JORNAL';
      case NewsType.portal: return 'PORTAL';
      case NewsType.social: return 'SOCIAL';
      case NewsType.agencia: return 'AGÊNCIA';
      case NewsType.video: return 'VÍDEO';
    }
  }

  Future<void> _launchUrl(String url, BuildContext context) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        // Fallback: tentar abrir a página principal do site
        final domain = uri.host;
        final fallbackUri = Uri.parse('https://$domain');
        if (await canLaunchUrl(fallbackUri)) {
          await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Não foi possível abrir o link'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class ControlPanelWidget extends StatelessWidget {
  final bool isMonitoring;
  final int articleCount;
  final DateTime lastUpdate;
  final VoidCallback onStartMonitoring;
  final VoidCallback onStopMonitoring;
  final VoidCallback onForceUpdate;
  final VoidCallback onGenerateReport;

  const ControlPanelWidget({
    Key? key,
    required this.isMonitoring,
    required this.articleCount,
    required this.lastUpdate,
    required this.onStartMonitoring,
    required this.onStopMonitoring,
    required this.onForceUpdate,
    required this.onGenerateReport,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                // Status Indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isMonitoring ? Colors.green[50] : Colors.grey[50],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isMonitoring ? Colors.green : Colors.grey,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isMonitoring ? Icons.circle : Icons.circle_outlined,
                        size: 12,
                        color: isMonitoring ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isMonitoring ? 'MONITORANDO' : 'PARADO',
                        style: TextStyle(
                          color: isMonitoring ? Colors.green : Colors.grey,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),

                // Botões de Controle
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: isMonitoring ? null : onStartMonitoring,
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Iniciar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: isMonitoring ? onStopMonitoring : null,
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('Parar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: onForceUpdate,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Atualizar Agora',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.blue[50],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: onGenerateReport,
                      icon: const Icon(Icons.article),
                      tooltip: 'Gerar Relatório',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.orange[50],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Informações
            Row(
              children: [
                _buildInfoItem(Icons.article, '$articleCount notícias'),
                const Spacer(),
                _buildInfoItem(Icons.access_time, _formatTime(lastUpdate)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime date) {
    return 'Última: ${DateFormat('HH:mm').format(date)}';
  }
}

class DateFilterWidget extends StatefulWidget {
  final DateTime? startDate;
  final DateTime? endDate;
  final Function(DateTime?, DateTime?) onDateChanged;

  const DateFilterWidget({
    Key? key,
    required this.startDate,
    required this.endDate,
    required this.onDateChanged,
  }) : super(key: key);

  @override
  _DateFilterWidgetState createState() => _DateFilterWidgetState();
}

class _DateFilterWidgetState extends State<DateFilterWidget> {
  late DateTime? _startDate;
  late DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _startDate = widget.startDate;
    _endDate = widget.endDate;
  }

  Future<void> _selectStartDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        widget.onDateChanged(_startDate, _endDate);
      });
    }
  }

  Future<void> _selectEndDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
        widget.onDateChanged(_startDate, _endDate);
      });
    }
  }

  void _clearDates() {
    setState(() {
      _startDate = null;
      _endDate = null;
      widget.onDateChanged(null, null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filtrar por Data:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Data Inicial:', style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => _selectStartDate(context),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                _startDate != null
                                    ? DateFormat('dd/MM/yyyy').format(_startDate!)
                                    : 'Selecionar data',
                                style: TextStyle(
                                  color: _startDate != null ? Colors.black : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Data Final:', style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => _selectEndDate(context),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                _endDate != null
                                    ? DateFormat('dd/MM/yyyy').format(_endDate!)
                                    : 'Selecionar data',
                                style: TextStyle(
                                  color: _endDate != null ? Colors.black : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_startDate != null || _endDate != null)
              TextButton(
                onPressed: _clearDates,
                child: const Text('Limpar filtros de data'),
              ),
          ],
        ),
      ),
    );
  }
}

// ========== PÁGINA PRINCIPAL ==========
class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<NewsArticle> _articles = [];
  List<NewsArticle> _filteredArticles = [];
  String _searchQuery = '';
  bool _isMonitoring = false;
  bool _isLoading = false;
  DateTime _lastUpdate = DateTime.now();

  // Filtros de data
  DateTime? _startDate;
  DateTime? _endDate;

  // Filtros de fonte
  Map<String, bool> _sourcesSelection = {};
  bool _allSourcesSelected = true;

  @override
  void initState() {
    super.initState();
    _initializeSources();
  }

  void _initializeSources() {
    // Inicializar todas as fontes como selecionadas
    for (var source in NewsSearchService._newsSources) {
      _sourcesSelection[source['name'] as String] = true;
    }
  }

  void _applyFilters() {
    List<NewsArticle> filtered = List.from(_articles);

    // Filtro por data
    if (_startDate != null || _endDate != null) {
      filtered = filtered.where((article) {
        final articleDate = DateTime(article.date.year, article.date.month, article.date.day);
        final start = _startDate != null
            ? DateTime(_startDate!.year, _startDate!.month, _startDate!.day)
            : DateTime(1900);
        final end = _endDate != null
            ? DateTime(_endDate!.year, _endDate!.month, _endDate!.day)
            : DateTime(2100);

        return articleDate.isAfter(start.subtract(const Duration(days: 1))) &&
            articleDate.isBefore(end.add(const Duration(days: 1)));
      }).toList();
    }

    // Filtro por fonte
    if (!_allSourcesSelected) {
      final selectedSources = _sourcesSelection.entries
          .where((entry) => entry.value)
          .map((entry) => entry.key)
          .toList();
      if (selectedSources.isNotEmpty) {
        filtered = filtered.where((article) => selectedSources.contains(article.source)).toList();
      }
    }

    // Filtro de busca
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((article) {
        return article.title.toLowerCase().contains(_searchQuery) ||
            article.content.toLowerCase().contains(_searchQuery) ||
            article.source.toLowerCase().contains(_searchQuery);
      }).toList();
    }

    setState(() {
      _filteredArticles = filtered;
    });
  }

  Future<void> _generateReport() async {
    try {
      // Gerar conteúdo HTML simples
      final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
    <title>Relatório PCDF Clipping</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #1a365d; color: white; padding: 20px; }
        .news-item { border: 1px solid #ddd; margin: 10px 0; padding: 15px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Relatório PCDF Clipping</h1>
        <p>Data: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}</p>
        <p>Total: ${_filteredArticles.length} notícias</p>
    </div>
    ${_filteredArticles.map((article) => '''
        <div class="news-item">
            <h3>${article.title}</h3>
            <p><strong>Fonte:</strong> ${article.source} | 
               <strong>Data:</strong> ${article.formattedDate} | 
               <strong>Score:</strong> ${article.relevanceScore}</p>
            <p>${article.content}</p>
        </div>
    ''').join()}
</body>
</html>
''';

      // Compartilhar como texto (solução universal)
      await Share.share(
        'Relatório PCDF Clipping\n\n' +
            'Data: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}\n' +
            'Total: ${_filteredArticles.length} notícias\n\n' +
            _filteredArticles.map((article) =>
            '• ${article.title}\n  Fonte: ${article.source} | Data: ${article.formattedDate} | Score: ${article.relevanceScore}'
            ).join('\n\n'),
        subject: 'Relatório PCDF Clipping',
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Relatório compartilhado com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PCDF Clipping'),
            Text(
              'Sistema de Monitoramento de Notícias',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1a365d),
        foregroundColor: Colors.white,
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Sistema Altos
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            color: const Color(0xFF2d3748),
            child: const Text(
              'SISTEMA ALTOS - MONITORAMENTO EM TEMPO REAL',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
          ),

          // Painel de Controle
          ControlPanelWidget(
            isMonitoring: _isMonitoring,
            articleCount: _filteredArticles.length,
            lastUpdate: _lastUpdate,
            onStartMonitoring: _startMonitoring,
            onStopMonitoring: _stopMonitoring,
            onForceUpdate: _forceUpdate,
            onGenerateReport: _generateReport,
          ),

          // Filtro de Data
          DateFilterWidget(
            startDate: _startDate,
            endDate: _endDate,
            onDateChanged: (start, end) {
              setState(() {
                _startDate = start;
                _endDate = end;
              });
              _applyFilters();
            },
          ),

          // Barra de Pesquisa
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: '🔍 Buscar notícias...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
                _applyFilters();
              },
            ),
          ),

          // Filtros de Fonte
          _buildSourcesFilter(),

          // Header do Feed
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                const Text(
                  '📰 FEED DE NOTÍCIAS',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1a365d),
                  ),
                ),
                const Spacer(),
                Text(
                  '${_filteredArticles.length} resultados',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Lista de Notícias
          Expanded(
            child: _buildNewsList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _forceUpdate,
        child: const Icon(Icons.refresh),
        backgroundColor: const Color(0xFF1a365d),
      ),
    );
  }

  Widget _buildSourcesFilter() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Fontes de Notícia:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _toggleAllSources,
                  child: Text(
                    _allSourcesSelected ? 'Desmarcar todas' : 'Marcar todas',
                    style: const TextStyle(
                      color: Colors.blue,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _sourcesSelection.entries.map((entry) {
                return FilterChip(
                  label: Text(entry.key),
                  selected: entry.value,
                  onSelected: (selected) {
                    setState(() {
                      _sourcesSelection[entry.key] = selected;
                      _allSourcesSelected = _sourcesSelection.values.every((v) => v);
                    });
                    _applyFilters();
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleAllSources() {
    setState(() {
      _allSourcesSelected = !_allSourcesSelected;
      for (var key in _sourcesSelection.keys) {
        _sourcesSelection[key] = _allSourcesSelected;
      }
    });
    _applyFilters();
  }

  Widget _buildNewsList() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Buscando notícias...'),
          ],
        ),
      );
    }

    if (_articles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            const Text(
              'Nenhuma notícia monitorada',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'Clique em "Iniciar" para começar o monitoramento',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_filteredArticles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.filter_list, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            const Text(
              'Nenhum resultado para os filtros aplicados',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                  _startDate = null;
                  _endDate = null;
                  _toggleAllSources();
                });
                _applyFilters();
              },
              child: const Text('Limpar todos os filtros'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _filteredArticles.length,
      itemBuilder: (context, index) {
        final article = _filteredArticles[index];
        return NewsItemWidget(
          article: article,
          onTap: () => _showArticleDetails(article),
        );
      },
    );
  }

  void _showArticleDetails(NewsArticle article) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(article.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('📰 ${article.source}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('📅 ${article.formattedDate} às ${article.formattedTime}'),
              Text('⭐ Score: ${article.relevanceScore}'),
              Text('👁️ Engajamento: ${article.engagementFormatted}'),
              const SizedBox(height: 16),
              const Text('📝 Conteúdo:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(article.content),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
          ElevatedButton(
            onPressed: () => _launchUrl(article.url, context),
            child: const Text('Abrir Notícia Original'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url, BuildContext context) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao abrir link: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _startMonitoring() {
    setState(() {
      _isMonitoring = true;
      _isLoading = true;
    });

    _fetchNews();
  }

  void _stopMonitoring() {
    setState(() {
      _isMonitoring = false;
    });
  }

  void _forceUpdate() {
    if (_isMonitoring) {
      _fetchNews();
    }
  }

  void _fetchNews() {
    setState(() {
      _isLoading = true;
    });

    // Simular busca com delay de rede
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;

      final newArticles = NewsSearchService.searchNews(
        count: 15,
        startDate: _startDate,
        endDate: _endDate,
      );

      setState(() {
        _articles.clear();
        _articles.addAll(newArticles);
        _lastUpdate = DateTime.now();
        _isLoading = false;
        _applyFilters();
      });
    });
  }
}

// ========== APLICAÇÃO PRINCIPAL ==========
class PCDFClippingApp extends StatelessWidget {
  const PCDFClippingApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PCDF Clipping',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1a365d),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}