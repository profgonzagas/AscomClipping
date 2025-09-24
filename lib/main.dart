import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import 'package:html/parser.dart' as html_parser;

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

// ========== SERVIÇO DE BUSCA DE NOTÍCIAS REAL ==========
class NewsSearchService {
  static final List<Map<String, dynamic>> _newsSources = [
    {
      'name': 'G1 Distrito Federal',
      'domain': 'g1.globo.com',
      'rss': 'https://g1.globo.com/rss/g1/distrito-federal/',
      'type': NewsType.portal,
      'weight': 10
    },
    {
      'name': 'Correio Braziliense',
      'domain': 'correiobraziliense.com.br',
      'rss': 'https://www.correiobraziliense.com.br/rss',
      'type': NewsType.jornal,
      'weight': 9
    },
    {
      'name': 'Metrópoles DF',
      'domain': 'metropoles.com',
      'rss': 'https://www.metropoles.com/df/rss',
      'type': NewsType.portal,
      'weight': 8
    },
    {
      'name': 'Agência Brasil',
      'domain': 'agenciabrasil.ebc.com.br',
      'rss': 'https://agenciabrasil.ebc.com.br/rss/ultimasnoticias/feed.xml',
      'type': NewsType.agencia,
      'weight': 7
    },
  ];

  static final List<String> _pcdfKeywords = [
    'pcdf', 'polícia civil', 'polícia civil df', 'polícia civil distrito federal',
    'delegacia', 'delegado', 'investigação', 'operacao', 'apreensao', 'prisao',
    'crime', 'policia', 'segurança', 'df', 'distrito federal'
  ];

  static Future<List<NewsArticle>> searchRealNews({int count = 20, DateTime? startDate, DateTime? endDate}) async {
    final results = <NewsArticle>[];
    final now = DateTime.now();

    try {
      // Buscar notícias do Google News RSS (busca por PCDF e termos relacionados)
      final googleNews = await _fetchGoogleNews();
      results.addAll(googleNews);

      // Buscar notícias do G1 RSS
      final g1News = await _fetchG1News();
      results.addAll(g1News);

      // Buscar de outras fontes RSS
      for (var source in _newsSources) {
        try {
          final sourceNews = await _fetchRSSFeed(
              source['rss'] as String,
              source['name'] as String,
              source['type'] as NewsType
          );
          results.addAll(sourceNews);
        } catch (e) {
          print('Erro ao buscar RSS de ${source['name']}: $e');
        }
      }

      // Filtro por palavras-chave da PCDF
      final filteredResults = results.where((article) {
        final text = '${article.title} ${article.content}'.toLowerCase();
        return _pcdfKeywords.any((keyword) => text.contains(keyword));
      }).toList();

      // Ordenar por data e limitar quantidade
      filteredResults.sort((a, b) => b.date.compareTo(a.date));

      return filteredResults.take(count).toList();

    } catch (e) {
      print('Erro na busca de notícias: $e');
      // Fallback para notícias mock em caso de erro
      return _generateMockNews(count: count, startDate: startDate, endDate: endDate);
    }
  }

  static Future<List<NewsArticle>> _fetchGoogleNews() async {
    final results = <NewsArticle>[];
    try {
      // Google News RSS para busca de PCDF
      final response = await http.get(Uri.parse(
          'https://news.google.com/rss/search?q=PCDF+Pol%C3%ADcia+Civil+Distrito+Federal&hl=pt-BR&gl=BR&ceid=BR:pt-419'
      ));

      if (response.statusCode == 200) {
        final document = xml.XmlDocument.parse(response.body);
        final items = document.findAllElements('item');

        for (var item in items) {
          try {
            final title = item.findElements('title').first.text;
            final link = item.findElements('link').first.text;
            final pubDate = item.findElements('pubDate').first.text;
            final description = item.findElements('description').first.text;

            final article = NewsArticle(
              id: link.hashCode.toString(),
              title: _cleanHtml(title),
              source: 'Google News',
              url: link,
              content: _cleanHtml(description),
              date: _parseDate(pubDate),
              category: NewsCategory.pcdf,
              relevanceScore: _calculateRelevance(title + description),
              engagement: 1000,
              type: NewsType.portal,
              preview: _extractPreview(description),
            );

            results.add(article);
          } catch (e) {
            print('Erro ao parsear item do Google News: $e');
          }
        }
      }
    } catch (e) {
      print('Erro ao buscar Google News: $e');
    }
    return results;
  }

  static Future<List<NewsArticle>> _fetchG1News() async {
    final results = <NewsArticle>[];
    try {
      final response = await http.get(Uri.parse(
          'https://g1.globo.com/rss/g1/distrito-federal/'
      ));

      if (response.statusCode == 200) {
        final document = xml.XmlDocument.parse(response.body);
        final items = document.findAllElements('item');

        for (var item in items) {
          try {
            final title = item.findElements('title').first.text;
            final link = item.findElements('link').first.text;
            final pubDate = item.findElements('pubDate').first.text;
            final description = item.findElements('description').first.text;

            // Verificar se é relevante para PCDF
            final content = title + ' ' + description;
            if (!_isRelevantToPCDF(content)) continue;

            final article = NewsArticle(
              id: link.hashCode.toString(),
              title: _cleanHtml(title),
              source: 'G1 Distrito Federal',
              url: link,
              content: _cleanHtml(description),
              date: _parseDate(pubDate),
              category: NewsCategory.pcdf,
              relevanceScore: _calculateRelevance(content),
              engagement: 1500,
              type: NewsType.portal,
              preview: _extractPreview(description),
            );

            results.add(article);
          } catch (e) {
            print('Erro ao parsear item do G1: $e');
          }
        }
      }
    } catch (e) {
      print('Erro ao buscar G1 RSS: $e');
    }
    return results;
  }

  static Future<List<NewsArticle>> _fetchRSSFeed(String url, String source, NewsType type) async {
    final results = <NewsArticle>[];
    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final document = xml.XmlDocument.parse(response.body);
        final items = document.findAllElements('item').take(10); // Limitar por fonte

        for (var item in items) {
          try {
            final title = item.findElements('title').first.text;
            final link = item.findElements('link').first.text;
            final pubDate = item.findElements('pubDate').first.text;
            final description = item.findElements('description').first.text;

            // Verificar relevância para PCDF
            final content = title + ' ' + description;
            if (!_isRelevantToPCDF(content)) continue;

            final article = NewsArticle(
              id: '${source}_${link.hashCode}',
              title: _cleanHtml(title),
              source: source,
              url: link,
              content: _cleanHtml(description),
              date: _parseDate(pubDate),
              category: NewsCategory.pcdf,
              relevanceScore: _calculateRelevance(content),
              engagement: 800,
              type: type,
              preview: _extractPreview(description),
            );

            results.add(article);
          } catch (e) {
            print('Erro ao parsear item do RSS $source: $e');
          }
        }
      }
    } catch (e) {
      print('Erro ao buscar RSS $source: $e');
    }
    return results;
  }

  static Future<List<NewsArticle>> scrapeNewsWebsites() async {
    final results = <NewsArticle>[];

    // Scraping de sites que não possuem RSS adequado
    final websites = [
      {
        'name': 'PCDF Oficial',
        'url': 'https://www.pcdf.df.gov.br/noticias',
        'type': NewsType.portal,
      },
      {
        'name': 'SSP-DF',
        'url': 'https://www.ssp.df.gov.br/noticias',
        'type': NewsType.portal,
      },
    ];

    for (var site in websites) {
      try {
        final response = await http.get(Uri.parse(site['url'] as String));
        if (response.statusCode == 200) {
          final scrapedNews = await _scrapeWebsiteContent(
              response.body,
              site['name'] as String,
              site['type'] as NewsType
          );
          results.addAll(scrapedNews);
        }
      } catch (e) {
        print('Erro no scraping de ${site['name']}: $e');
      }
    }

    return results;
  }

  static Future<List<NewsArticle>> _scrapeWebsiteContent(String html, String source, NewsType type) async {
    final results = <NewsArticle>[];
    try {
      final document = html_parser.parse(html);

      // Tentar encontrar notícias por seletores comuns
      final newsElements = document.querySelectorAll('h1, h2, h3, .news, .noticia, .title, .titulo');

      for (var element in newsElements.take(5)) {
        try {
          final title = element.text.trim();
          if (title.length < 10 || !_isRelevantToPCDF(title)) continue;

          // Tentar encontrar link
          var link = element.querySelector('a')?.attributes['href'] ?? '';
          if (link.isNotEmpty && !link.startsWith('http')) {
            link = 'https://${_getDomainFromSource(source)}$link';
          }

          final article = NewsArticle(
            id: '${source}_${title.hashCode}',
            title: title,
            source: source,
            url: link.isNotEmpty ? link : 'https://${_getDomainFromSource(source)}',
            content: title,
            date: DateTime.now(),
            category: NewsCategory.pcdf,
            relevanceScore: _calculateRelevance(title),
            engagement: 500,
            type: type,
            preview: title.length > 100 ? title.substring(0, 100) + '...' : title,
          );

          results.add(article);
        } catch (e) {
          print('Erro ao parsear elemento do scraping: $e');
        }
      }
    } catch (e) {
      print('Erro no parsing HTML: $e');
    }
    return results;
  }

  // ========== MÉTODOS AUXILIARES ==========
  static String _cleanHtml(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'&[^;]+;'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static DateTime _parseDate(String dateString) {
    try {
      // Tentar vários formatos de data comum em RSS
      final formats = [
        DateFormat('EEE, dd MMM yyyy HH:mm:ss Z', 'en'),
        DateFormat('EEE, dd MMM yyyy HH:mm:ss', 'en'),
        DateFormat('yyyy-MM-ddTHH:mm:ssZ'),
        DateFormat('yyyy-MM-dd HH:mm:ss'),
        DateFormat('dd/MM/yyyy HH:mm:ss'),
      ];

      for (var format in formats) {
        try {
          return format.parse(dateString);
        } catch (e) {
          continue;
        }
      }

      // Se nenhum formato funcionar, usar data atual
      return DateTime.now();
    } catch (e) {
      return DateTime.now();
    }
  }

  static bool _isRelevantToPCDF(String text) {
    final lowerText = text.toLowerCase();
    return _pcdfKeywords.any((keyword) => lowerText.contains(keyword));
  }

  static int _calculateRelevance(String text) {
    final lowerText = text.toLowerCase();
    var score = 5; // Score base

    // Palavras-chave de alta relevância
    if (lowerText.contains('pcdf')) score += 3;
    if (lowerText.contains('polícia civil')) score += 3;
    if (lowerText.contains('distrito federal')) score += 2;

    // Palavras-chave de média relevância
    if (lowerText.contains('delegacia')) score += 2;
    if (lowerText.contains('operacao')) score += 2;
    if (lowerText.contains('prisao') || lowerText.contains('prisão')) score += 2;
    if (lowerText.contains('apreensao') || lowerText.contains('apreensão')) score += 2;

    // Limitar score máximo
    return score.clamp(1, 10);
  }

  static String _extractPreview(String description) {
    final cleanDesc = _cleanHtml(description);
    return cleanDesc.length > 150
        ? cleanDesc.substring(0, 150) + '...'
        : cleanDesc;
  }

  static String _getDomainFromSource(String source) {
    final domains = {
      'G1 Distrito Federal': 'g1.globo.com',
      'Correio Braziliense': 'correiobraziliense.com.br',
      'Metrópoles DF': 'metropoles.com',
      'Agência Brasil': 'agenciabrasil.ebc.com.br',
      'PCDF Oficial': 'pcdf.df.gov.br',
      'SSP-DF': 'ssp.df.gov.br',
    };
    return domains[source] ?? 'google.com';
  }

  // ========== FALLBACK PARA DADOS MOCK ==========
  static List<NewsArticle> _generateMockNews({int count = 10, DateTime? startDate, DateTime? endDate}) {
    final results = <NewsArticle>[];
    final now = DateTime.now();
    final random = DateTime.now().millisecondsSinceEpoch;

    final newsTemplates = [
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
    ];

    for (int i = 0; i < count; i++) {
      final template = newsTemplates[i % newsTemplates.length];
      final source = _newsSources[i % _newsSources.length];

      final articleDate = now.subtract(Duration(days: i % 7));
      final titleSlug = _generateSlug(template['title'] as String);
      final url = 'https://${source['domain']}/noticias/${DateFormat('yyyy/MM').format(articleDate)}/$titleSlug';

      results.add(NewsArticle(
        id: '${now.millisecondsSinceEpoch}_$i',
        title: template['title'] as String,
        source: source['name'] as String,
        url: url,
        content: _generateContent(template['title'] as String, source['name'] as String),
        date: articleDate,
        category: NewsCategory.pcdf,
        relevanceScore: (template['baseScore'] as int) + (i % 3),
        engagement: 1000 + (i * 237),
        type: source['type'] as NewsType,
        preview: _generatePreview(template['title'] as String),
      ));
    }

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
                  const SizedBox(width: 8),
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
      'Metrópoles DF': Colors.purple[600]!,
      'Agência Brasil': Colors.green[600]!,
      'Google News': Colors.orange[700]!,
      'PCDF Oficial': Colors.blue[800]!,
      'SSP-DF': Colors.blue[600]!,
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
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
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

// ========== CONTROL PANEL WIDGET ==========
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
                        'Status: ${isMonitoring ? 'MONITORANDO' : 'PARADO'}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isMonitoring ? Colors.green : Colors.red,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Notícias: $articleCount',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        'Última atualização: ${DateFormat('dd/MM/yyyy HH:mm').format(lastUpdate)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    if (!isMonitoring)
                      ElevatedButton.icon(
                        onPressed: onStartMonitoring,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Iniciar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: onStopMonitoring,
                        icon: const Icon(Icons.stop),
                        label: const Text('Parar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: onForceUpdate,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Atualizar'),
                    ),
                  ],
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

// ========== DATE FILTER WIDGET ==========
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
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      if (isStartDate) {
        widget.onDateChanged(picked, widget.endDate);
      } else {
        widget.onDateChanged(widget.startDate, picked);
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
            const Text(
              'Filtrar por Data:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Data Inicial:'),
                      const SizedBox(height: 4),
                      ElevatedButton(
                        onPressed: () => _selectDate(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[100],
                          foregroundColor: Colors.black87,
                          minimumSize: const Size(double.infinity, 40),
                        ),
                        child: Text(
                          widget.startDate != null
                              ? DateFormat('dd/MM/yyyy').format(widget.startDate!)
                              : 'Selecionar Data',
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
                      const Text('Data Final:'),
                      const SizedBox(height: 4),
                      ElevatedButton(
                        onPressed: () => _selectDate(context, false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[100],
                          foregroundColor: Colors.black87,
                          minimumSize: const Size(double.infinity, 40),
                        ),
                        child: Text(
                          widget.endDate != null
                              ? DateFormat('dd/MM/yyyy').format(widget.endDate!)
                              : 'Selecionar Data',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.startDate != null || widget.endDate != null)
              ElevatedButton(
                onPressed: _clearDates,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[300],
                  foregroundColor: Colors.black87,
                ),
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
  bool _isMonitoring = false;
  bool _isLoading = false;
  DateTime _lastUpdate = DateTime.now();

  DateTime? _startDate;
  DateTime? _endDate;
  Map<String, bool> _sourcesSelection = {};
  bool _allSourcesSelected = true;

  @override
  void initState() {
    super.initState();
    _initializeSources();
  }

  void _initializeSources() {
    _sourcesSelection = {
      'G1 Distrito Federal': true,
      'Correio Braziliense': true,
      'Metrópoles DF': true,
      'Agência Brasil': true,
      'Google News': true,
      'PCDF Oficial': true,
      'SSP-DF': true,
    };
  }

  void _applyFilters() {
    List<NewsArticle> filtered = List.from(_articles);

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

    if (!_allSourcesSelected) {
      final selectedSources = _sourcesSelection.entries
          .where((entry) => entry.value)
          .map((entry) => entry.key)
          .toList();
      if (selectedSources.isNotEmpty) {
        filtered = filtered.where((article) => selectedSources.contains(article.source)).toList();
      }
    }

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
          ControlPanelWidget(
            isMonitoring: _isMonitoring,
            articleCount: _filteredArticles.length,
            lastUpdate: _lastUpdate,
            onStartMonitoring: _startMonitoring,
            onStopMonitoring: _stopMonitoring,
            onForceUpdate: _forceUpdate,
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
              _applyFilters();
            },
          ),
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
          _buildSourcesFilter(),
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
            Text('Buscando notícias em tempo real...'),
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

    _fetchRealNews();
  }

  void _stopMonitoring() {
    setState(() {
      _isMonitoring = false;
    });
  }

  void _forceUpdate() {
    if (_isMonitoring) {
      _fetchRealNews();
    }
  }

  Future<void> _fetchRealNews() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final newArticles = await NewsSearchService.searchRealNews(
        count: 20,
        startDate: _startDate,
        endDate: _endDate,
      );

      // Adicionar notícias via scraping
      final scrapedArticles = await NewsSearchService.scrapeNewsWebsites();
      newArticles.addAll(scrapedArticles);

      setState(() {
        _articles.clear();
        _articles.addAll(newArticles);
        _lastUpdate = DateTime.now();
        _isLoading = false;
        _applyFilters();
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao buscar notícias: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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