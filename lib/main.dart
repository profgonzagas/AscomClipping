import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import 'dart:convert';

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
  String get formattedDateTime => '$formattedDate às $formattedTime';

  String get engagementFormatted {
    if (engagement > 1000000) return '${(engagement / 1000000).toStringAsFixed(1)}M';
    if (engagement > 1000) return '${(engagement / 1000).toStringAsFixed(1)}k';
    return engagement.toString();
  }

  String get relevanceText {
    if (relevanceScore >= 8) return 'Alta Relevância';
    if (relevanceScore >= 5) return 'Média Relevância';
    return 'Baixa Relevância';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'source': source,
      'url': url,
      'content': content,
      'date': date.toIso8601String(),
      'category': category.toString(),
      'relevanceScore': relevanceScore,
      'engagement': engagement,
      'type': type.toString(),
      'preview': preview,
      'isRead': isRead,
    };
  }
}

// ========== SERVIÇO DE BUSCA DE NOTÍCIAS REAL ==========
class NewsSearchService {
  static final List<Map<String, dynamic>> _newsSources = [
    {
      'name': 'G1 Distrito Federal',
      'rss': 'https://g1.globo.com/rss/g1/distrito-federal/',
      'type': NewsType.portal,
      'weight': 10
    },
    {
      'name': 'Correio Braziliense',
      'rss': 'https://www.correiobraziliense.com.br/rss',
      'type': NewsType.jornal,
      'weight': 9
    },
    {
      'name': 'Metrópoles DF',
      'rss': 'https://www.metropoles.com/feed',
      'type': NewsType.portal,
      'weight': 8
    },
    {
      'name': 'Agência Brasil',
      'rss': 'https://agenciabrasil.ebc.com.br/rss/ultimasnoticias/feed.xml',
      'type': NewsType.agencia,
      'weight': 7
    },
    {
      'name': 'Jornal de Brasília',
      'rss': 'https://www.jornaldebrasilia.com.br/feed/',
      'type': NewsType.jornal,
      'weight': 6
    },
    {
      'name': 'Brasil 61',
      'rss': 'https://brasil61.com/n/feed.rss',
      'type': NewsType.portal,
      'weight': 5
    },
  ];

  static final List<String> _pcdfKeywords = [
    'pcdf', 'polícia civil', 'polícia civil df', 'polícia civil distrito federal',
    'delegacia', 'delegado', 'investigação', 'inquérito', 'prisão', 'prisao',
    'operacao', 'operação', 'apreensão', 'apreensao', 'flagrante', 'mandado',
    'crime', 'criminal', 'segurança pública', 'seguranca publica', 'df'
  ];

  static Future<List<NewsArticle>> searchRealNews({int count = 50, DateTime? startDate, DateTime? endDate}) async {
    final results = <NewsArticle>[];

    try {
      print('Buscando notícias em tempo real...');

      // Buscar de todas as fontes RSS
      for (var source in _newsSources) {
        try {
          final sourceNews = await _fetchRSSFeed(
            source['rss'] as String,
            source['name'] as String,
            source['type'] as NewsType,
            startDate: startDate,
            endDate: endDate,
          );
          results.addAll(sourceNews);
          print('${source['name']}: ${sourceNews.length} notícias');

          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          print('Erro na fonte ${source['name']}: $e');
        }
      }

      // Buscar notícias de segurança pública
      final securityNews = await _fetchSecurityNews(startDate: startDate, endDate: endDate);
      results.addAll(securityNews);

      // Remover duplicatas
      final uniqueResults = _removeDuplicates(results);
      print('Total único: ${uniqueResults.length} notícias');

      // Filtrar por relevância para PCDF
      final filteredResults = uniqueResults.where((article) {
        final text = '${article.title} ${article.content} ${article.preview}'.toLowerCase();
        return _pcdfKeywords.any((keyword) => text.contains(keyword.toLowerCase()));
      }).toList();

      print('Após filtro PCDF: ${filteredResults.length} notícias');

      // Ordenar por data e relevância
      filteredResults.sort((a, b) {
        final dateCompare = b.date.compareTo(a.date);
        if (dateCompare != 0) return dateCompare;
        return b.relevanceScore.compareTo(a.relevanceScore);
      });

      return filteredResults.take(count).toList();

    } catch (e) {
      print('Erro geral na busca: $e');
      return [];
    }
  }

  static Future<List<NewsArticle>> _fetchRSSFeed(
      String url,
      String source,
      NewsType type, {
        DateTime? startDate,
        DateTime? endDate,
      }) async {
    final results = <NewsArticle>[];

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'application/rss+xml, text/xml, */*',
        },
      );

      if (response.statusCode == 200) {
        final document = xml.XmlDocument.parse(response.body);
        final items = document.findAllElements('item').take(15);

        for (var item in items) {
          try {
            final title = item.findElements('title').firstOrNull?.text ?? 'Sem título';
            final link = item.findElements('link').firstOrNull?.text ?? '';
            final pubDate = item.findElements('pubDate').firstOrNull?.text ?? '';
            final description = item.findElements('description').firstOrNull?.text ?? '';
            final content = item.findElements('content:encoded').firstOrNull?.text ?? description;

            if (title == 'Sem título' || link.isEmpty) continue;

            final articleDate = _parseDate(pubDate);

            // Filtrar por data
            if (startDate != null && articleDate.isBefore(startDate)) continue;
            if (endDate != null && articleDate.isAfter(endDate)) continue;

            final cleanTitle = _cleanHtml(title);
            final cleanContent = _cleanHtml(content);

            final relevanceScore = _calculateRelevance(cleanTitle + cleanContent);

            final article = NewsArticle(
              id: '${source}_${link.hashCode}',
              title: cleanTitle,
              source: source,
              url: link,
              content: cleanContent,
              date: articleDate,
              category: NewsCategory.pcdf,
              relevanceScore: relevanceScore,
              engagement: _calculateEngagement(source),
              type: type,
              preview: _extractPreview(cleanContent),
            );

            results.add(article);
          } catch (e) {
            print('Erro ao processar item: $e');
          }
        }
      }
    } catch (e) {
      print('Erro no RSS $source: $e');
    }

    return results;
  }

  static Future<List<NewsArticle>> _fetchSecurityNews({DateTime? startDate, DateTime? endDate}) async {
    final results = <NewsArticle>[];

    try {
      // Fontes especializadas em segurança
      final securityFeeds = [
        'https://www.poder360.com.br/feed/',
        'https://www.cnnbrasil.com.br/seguranca/feed/',
      ];

      for (var feed in securityFeeds) {
        try {
          final news = await _fetchRSSFeed(feed, 'Segurança Pública', NewsType.portal,
              startDate: startDate, endDate: endDate);

          // Filtrar por termos relacionados a DF/PCDF
          final filtered = news.where((article) {
            final text = article.title.toLowerCase() + article.content.toLowerCase();
            return text.contains('df') ||
                text.contains('distrito federal') ||
                text.contains('brasília') ||
                text.contains('pcdf');
          }).toList();

          results.addAll(filtered);
        } catch (e) {
          print('Erro no feed de segurança: $e');
        }
      }
    } catch (e) {
      print('Erro geral em segurança: $e');
    }

    return results;
  }

  static List<NewsArticle> _removeDuplicates(List<NewsArticle> articles) {
    final seenUrls = <String>{};
    final uniqueArticles = <NewsArticle>[];

    for (var article in articles) {
      if (!seenUrls.contains(article.url)) {
        seenUrls.add(article.url);
        uniqueArticles.add(article);
      }
    }

    return uniqueArticles;
  }

  // ========== MÉTODOS AUXILIARES ==========
  static String _cleanHtml(String htmlString) {
    return htmlString
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'&nbsp;'), ' ')
        .replaceAll(RegExp(r'&amp;'), '&')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static DateTime _parseDate(String dateString) {
    try {
      final formats = [
        'EEE, dd MMM yyyy HH:mm:ss Z',
        'EEE, dd MMM yyyy HH:mm:ss',
        'yyyy-MM-ddTHH:mm:ssZ',
        'yyyy-MM-dd HH:mm:ss',
        'dd/MM/yyyy HH:mm:ss',
      ];

      for (var format in formats) {
        try {
          return DateFormat(format).parse(dateString);
        } catch (_) {
          continue;
        }
      }

      return DateTime.now();
    } catch (e) {
      return DateTime.now();
    }
  }

  static int _calculateRelevance(String text) {
    final lowerText = text.toLowerCase();
    var score = 3;

    if (lowerText.contains('pcdf')) score += 4;
    if (lowerText.contains('polícia civil')) score += 4;
    if (lowerText.contains('distrito federal')) score += 2;
    if (lowerText.contains('df')) score += 1;
    if (lowerText.contains('delegacia')) score += 2;
    if (lowerText.contains('operacao') || lowerText.contains('operação')) score += 2;
    if (lowerText.contains('prisao') || lowerText.contains('prisão')) score += 2;
    if (lowerText.contains('investigação')) score += 2;
    if (lowerText.contains('segurança')) score += 1;
    if (lowerText.contains('crime')) score += 1;

    return score.clamp(1, 10);
  }

  static int _calculateEngagement(String source) {
    final engagementMap = {
      'G1 Distrito Federal': 5000,
      'Correio Braziliense': 4000,
      'Metrópoles DF': 3000,
      'Agência Brasil': 2000,
      'Jornal de Brasília': 1500,
      'Brasil 61': 1000,
      'Segurança Pública': 1200,
    };
    return engagementMap[source] ?? 500;
  }

  static String _extractPreview(String content) {
    return content.length > 120 ? content.substring(0, 120) + '...' : content;
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
              Row(
                children: [
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
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () => _launchUrl(article.url, context),
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: const Text('Abrir'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1a365d),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
      'Metrópoles DF': Colors.purple[600]!,
      'Agência Brasil': Colors.green[600]!,
      'Jornal de Brasília': Colors.orange[600]!,
      'Brasil 61': Colors.red[600]!,
      'Segurança Pública': Colors.blue[600]!,
    };
    return colors[source] ?? Colors.grey[700]!;
  }

  Color _getScoreColor(int score) {
    if (score >= 8) return Colors.green[700]!;
    if (score >= 6) return Colors.orange[700]!;
    return Colors.red[700]!;
  }

  Future<void> _launchUrl(String url, BuildContext context) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o link')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }
}

class ControlPanelWidget extends StatelessWidget {
  final bool isMonitoring;
  final int articleCount;
  final DateTime lastUpdate;
  final VoidCallback onRefresh;
  final VoidCallback onGenerateReport;

  const ControlPanelWidget({
    Key? key,
    required this.isMonitoring,
    required this.articleCount,
    required this.lastUpdate,
    required this.onRefresh,
    required this.onGenerateReport,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status: ${isMonitoring ? 'ATIVO' : 'INATIVO'}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isMonitoring ? Colors.green : Colors.red,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Notícias: $articleCount',
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      Text(
                        'Última atualização: ${DateFormat('dd/MM/yyyy HH:mm').format(lastUpdate)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Atualizar'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onGenerateReport,
              icon: const Icon(Icons.article),
              label: const Text('Gerar Relatório'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1a365d),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 40),
              ),
            ),
          ],
        ),
      ),
    );
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
  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate ? widget.startDate ?? DateTime.now() : widget.endDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );

    if (picked != null) {
      if (isStartDate) {
        widget.onDateChanged(picked, widget.endDate);
      } else {
        final endOfDay = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        widget.onDateChanged(widget.startDate, endOfDay);
      }
    }
  }

  void _clearDates() {
    widget.onDateChanged(null, null);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Filtrar por Data:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Data Inicial:'),
                      ElevatedButton(
                        onPressed: () => _selectDate(context, true),
                        child: Text(widget.startDate != null
                            ? DateFormat('dd/MM/yyyy').format(widget.startDate!)
                            : 'Selecionar'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Data Final:'),
                      ElevatedButton(
                        onPressed: () => _selectDate(context, false),
                        child: Text(widget.endDate != null
                            ? DateFormat('dd/MM/yyyy').format(widget.endDate!)
                            : 'Selecionar'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (widget.startDate != null || widget.endDate != null)
              ElevatedButton(
                onPressed: _clearDates,
                child: const Text('Limpar Filtros'),
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
  bool _isLoading = false;
  DateTime _lastUpdate = DateTime.now();
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _loadNews();
  }

  Future<void> _loadNews() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final newArticles = await NewsSearchService.searchRealNews(
        startDate: _startDate,
        endDate: _endDate,
      );

      setState(() {
        _articles.clear();
        _articles.addAll(newArticles);
        _filteredArticles = List.from(_articles);
        _lastUpdate = DateTime.now();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar notícias: $e')),
      );
    }
  }

  void _applyFilters() {
    List<NewsArticle> filtered = List.from(_articles);

    if (_startDate != null || _endDate != null) {
      filtered = filtered.where((article) {
        final start = _startDate ?? DateTime(1900);
        final end = _endDate ?? DateTime(2100);
        return article.date.isAfter(start) && article.date.isBefore(end);
      }).toList();
    }

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((article) {
        return article.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            article.content.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    setState(() {
      _filteredArticles = filtered;
    });
  }

  Future<void> _generateReport() async {
    if (_filteredArticles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhuma notícia para gerar relatório')),
      );
      return;
    }

    try {
      final reportContent = '''
RELATÓRIO PCDF CLIPPING

Data: ${DateFormat('dd/MM/yyyy às HH:mm').format(DateTime.now())}
Total de notícias: ${_filteredArticles.length}

${_filteredArticles.map((article) => '''
📰 ${article.title}
   Fonte: ${article.source}
   Data: ${article.formattedDateTime}
   Relevância: ${article.relevanceScore}/10
   URL: ${article.url}
${'-' * 50}
''').join('\n')}
      ''';

      await Share.share(reportContent);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao gerar relatório: $e')),
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
            Text('Sistema de Monitoramento', style: TextStyle(fontSize: 12)),
          ],
        ),
        backgroundColor: const Color(0xFF1a365d),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          ControlPanelWidget(
            isMonitoring: true,
            articleCount: _filteredArticles.length,
            lastUpdate: _lastUpdate,
            onRefresh: _loadNews,
            onGenerateReport: _generateReport,
          ),
          DateFilterWidget(
            startDate: _startDate,
            endDate: _endDate,
            onDateChanged: (start, end) {
              setState(() {
                _startDate = start;
                _endDate = end;
              });
              _loadNews();
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar notícias...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
                _applyFilters();
              },
            ),
          ),
          Expanded(
            child: _buildNewsList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadNews,
        child: const Icon(Icons.refresh),
        backgroundColor: const Color(0xFF1a365d),
      ),
    );
  }

  Widget _buildNewsList() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Buscando notícias em tempo real...'),
          ],
        ),
      );
    }

    if (_filteredArticles.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Nenhuma notícia encontrada'),
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
              Text('Fonte: ${article.source}'),
              Text('Data: ${article.formattedDateTime}'),
              Text('Relevância: ${article.relevanceScore}/10'),
              const SizedBox(height: 16),
              const Text('Conteúdo:', style: TextStyle(fontWeight: FontWeight.bold)),
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
            child: const Text('Abrir Notícia'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url, BuildContext context) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao abrir link: $e')),
      );
    }
  }
}

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
        ),
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}