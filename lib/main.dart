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

// ========== SERVIÇO DE BUSCA DE NOTÍCIAS CORRIGIDO ==========
class NewsSearchService {
  static final List<Map<String, dynamic>> _newsSources = [
    {
      'name': 'Agência Brasil',
      'domain': 'agenciabrasil.ebc.com.br',
      'rss': 'https://agenciabrasil.ebc.com.br/rss/ultimasnoticias/feed.xml',
      'type': NewsType.agencia,
      'weight': 10
    },
    {
      'name': 'Jornal de Brasília',
      'domain': 'jornaldebrasilia.com.br',
      'rss': 'https://www.jornaldebrasilia.com.br/feed/',
      'type': NewsType.jornal,
      'weight': 9
    },
    {
      'name': 'G1 Distrito Federal',
      'domain': 'g1.globo.com',
      'rss': 'https://g1.globo.com/rss/g1/distrito-federal/',
      'type': NewsType.portal,
      'weight': 8
    },
    {
      'name': 'Correio Braziliense',
      'domain': 'correiobraziliense.com.br',
      'rss': 'https://www.correiobraziliense.com.br/rss/ultimas-noticias',
      'type': NewsType.jornal,
      'weight': 7
    },
    {
      'name': 'Metrópoles DF',
      'domain': 'metropoles.com',
      'rss': 'https://www.metropoles.com/df/rss',
      'type': NewsType.portal,
      'weight': 6
    },
    {
      'name': 'Brasil 61',
      'domain': 'brasil61.com',
      'rss': 'https://brasil61.com/feed',
      'type': NewsType.portal,
      'weight': 5
    },
    {
      'name': 'R7 Distrito Federal',
      'domain': 'r7.com',
      'rss': 'https://r7.com/rss/editorias/distrito-federal',
      'type': NewsType.portal,
      'weight': 4
    },
    {
      'name': 'UOL Notícias DF',
      'domain': 'uol.com.br',
      'rss': 'https://rss.uol.com.br/feed/noticias.xml',
      'type': NewsType.portal,
      'weight': 3
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
      print('Iniciando busca de notícias em ${_newsSources.length} fontes...');

      // Buscar de todas as fontes RSS em paralelo
      final List<Future<List<NewsArticle>>> rssFutures = [];

      for (var source in _newsSources) {
        rssFutures.add(_fetchRSSFeed(
          source['rss'] as String,
          source['name'] as String,
          source['type'] as NewsType,
          startDate: startDate,
          endDate: endDate,
        ));

        // Pequeno delay para evitar sobrecarga
        await Future.delayed(const Duration(milliseconds: 100));
      }

      final rssResults = await Future.wait(rssFutures);
      for (var sourceNews in rssResults) {
        results.addAll(sourceNews);
      }

      print('Total de notícias brutas: ${results.length}');

      // Buscar notícias do Google News separadamente
      final googleNews = await _fetchGoogleNews(startDate: startDate, endDate: endDate);
      results.addAll(googleNews);
      print('Com Google News: ${results.length} notícias');

      // Remover duplicatas baseadas no título e URL
      final uniqueResults = _removeDuplicates(results);
      print('Total único: ${uniqueResults.length} notícias');

      // Filtro por palavras-chave da PCDF (mais flexível)
      final filteredResults = uniqueResults.where((article) {
        final text = '${article.title} ${article.content} ${article.preview}'.toLowerCase();
        return _pcdfKeywords.any((keyword) => text.contains(keyword.toLowerCase()));
      }).toList();

      print('Após filtro PCDF: ${filteredResults.length} notícias');

      // Se tiver poucas notícias, buscar notícias de segurança pública em geral
      List<NewsArticle> finalResults;
      if (filteredResults.length < 10) {
        print('Poucas notícias PCDF encontradas. Buscando notícias de segurança geral...');
        final securityNews = await _fetchSecurityNews(startDate: startDate, endDate: endDate);
        finalResults = [...filteredResults, ...securityNews];
        finalResults = _removeDuplicates(finalResults);
        print('Com notícias de segurança: ${finalResults.length} notícias');
      } else {
        finalResults = filteredResults;
      }

      // Ordenar por data e relevância
      finalResults.sort((a, b) {
        final dateCompare = b.date.compareTo(a.date);
        if (dateCompare != 0) return dateCompare;
        return b.relevanceScore.compareTo(a.relevanceScore);
      });

      // Limitar ao número solicitado
      return finalResults.take(count).toList();

    } catch (e) {
      print('Erro na busca de notícias: $e');
      // Em caso de erro, retornar notícias de exemplo
      return _getFallbackNews();
    }
  }

  static Future<List<NewsArticle>> _fetchGoogleNews({DateTime? startDate, DateTime? endDate}) async {
    final results = <NewsArticle>[];
    try {
      // URL do Google News RSS para busca de notícias sobre PCDF e segurança no DF
      final queries = [
        'pcdf+distrito+federal',
        'polícia+civil+df',
        'segurança+pública+brasília',
        'crime+df',
        'delegacia+distrito+federal'
      ];

      for (var query in queries) {
        final encodedQuery = Uri.encodeQueryComponent(query);
        final rssUrl = 'https://news.google.com/rss/search?q=$encodedQuery&hl=pt-BR&gl=BR&ceid=BR:pt-419';

        print('Buscando Google News: $query');

        final response = await http.get(
          Uri.parse(rssUrl),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            'Accept': 'application/rss+xml, text/xml, */*',
          },
        );

        if (response.statusCode == 200) {
          final document = xml.XmlDocument.parse(response.body);
          final items = document.findAllElements('item').take(10);

          for (var item in items) {
            try {
              final titleElement = item.findElements('title').firstOrNull;
              final linkElement = item.findElements('link').firstOrNull;
              final pubDateElement = item.findElements('pubDate').firstOrNull;
              final descriptionElement = item.findElements('description').firstOrNull;

              if (titleElement == null || linkElement == null) continue;

              final title = titleElement.text;
              final link = linkElement.text;
              final pubDate = pubDateElement?.text ?? DateTime.now().toString();
              final description = descriptionElement?.text ?? '';

              final articleDate = _parseDate(pubDate);

              // Filtrar por data se especificado
              if (startDate != null && articleDate.isBefore(startDate)) continue;
              if (endDate != null && articleDate.isAfter(endDate)) continue;

              final cleanTitle = _cleanHtml(title);
              final cleanContent = _cleanHtml(description);

              final relevanceScore = _calculateRelevance(cleanTitle + cleanContent);

              final article = NewsArticle(
                id: 'googlenews_${link.hashCode}',
                title: cleanTitle,
                source: 'Google News',
                url: link,
                content: cleanContent,
                date: articleDate,
                category: NewsCategory.pcdf,
                relevanceScore: relevanceScore,
                engagement: 1500,
                type: NewsType.portal,
                preview: _extractPreview(cleanContent),
              );

              results.add(article);
            } catch (e) {
              print('Erro ao parsear item do Google News: $e');
            }
          }
        } else {
          print('Erro HTTP ${response.statusCode} para Google News - Query: $query');
        }

        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      print('Erro ao buscar Google News: $e');
    }

    print('Google News retornou: ${results.length} notícias');
    return results;
  }

  static Future<List<NewsArticle>> _fetchSecurityNews({DateTime? startDate, DateTime? endDate}) async {
    final results = <NewsArticle>[];
    final securitySources = [
      {
        'name': 'CNN Brasil Segurança',
        'rss': 'https://www.cnnbrasil.com.br/seguridad/rss/',
        'type': NewsType.portal,
      },
      {
        'name': 'Terra Segurança',
        'rss': 'https://www.terra.com.br/rss/seguranca/',
        'type': NewsType.portal,
      },
    ];

    try {
      for (var source in securitySources) {
        final sourceResults = await _fetchRSSFeed(
          source['rss'] as String,
          source['name'] as String,
          source['type'] as NewsType,
          startDate: startDate,
          endDate: endDate,
        );

        // Filtrar por termos de segurança
        final filtered = sourceResults.where((article) {
          final text = '${article.title} ${article.content}'.toLowerCase();
          return text.contains('segurança') ||
              text.contains('polícia') ||
              text.contains('crime') ||
              text.contains('df') ||
              text.contains('distrito federal');
        }).toList();

        results.addAll(filtered);
      }
    } catch (e) {
      print('Erro ao buscar notícias de segurança: $e');
    }

    return results;
  }

  static List<NewsArticle> _removeDuplicates(List<NewsArticle> articles) {
    final seenTitles = <String>{};
    final seenUrls = <String>{};
    final uniqueArticles = <NewsArticle>[];

    for (var article in articles) {
      final normalizedTitle = article.title.toLowerCase().trim();
      final normalizedUrl = article.url.toLowerCase().trim();

      if (!seenTitles.contains(normalizedTitle) && !seenUrls.contains(normalizedUrl)) {
        seenTitles.add(normalizedTitle);
        seenUrls.add(normalizedUrl);
        uniqueArticles.add(article);
      }
    }

    return uniqueArticles;
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

      print('Buscando RSS: $source - Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final document = xml.XmlDocument.parse(response.body);
        final items = document.findAllElements('item').take(20);

        for (var item in items) {
          try {
            final titleElement = item.findElements('title').firstOrNull;
            final linkElement = item.findElements('link').firstOrNull;
            final pubDateElement = item.findElements('pubDate').firstOrNull;
            final descriptionElement = item.findElements('description').firstOrNull;
            final contentElement = item.findElements('content:encoded').firstOrNull;

            if (titleElement == null || linkElement == null) continue;

            final title = titleElement.text;
            final link = linkElement.text;
            final pubDate = pubDateElement?.text ?? DateTime.now().toString();
            final description = descriptionElement?.text ?? '';
            final content = contentElement?.text ?? description;

            final articleDate = _parseDate(pubDate);

            // Filtrar por data se especificado
            if (startDate != null && articleDate.isBefore(startDate)) continue;
            if (endDate != null && articleDate.isAfter(endDate)) continue;

            final cleanTitle = _cleanHtml(title);
            final cleanContent = _cleanHtml(content.isNotEmpty ? content : description);

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
            print('Erro ao parsear item do RSS $source: $e');
          }
        }
        print('$source: ${results.length} notícias processadas');
      } else {
        print('Erro HTTP ${response.statusCode} para $source - URL: $url');
      }
    } catch (e) {
      print('Erro ao buscar RSS $source: $e');
    }
    return results;
  }

  // ========== MÉTODOS AUXILIARES CORRIGIDOS ==========
  static String _cleanHtml(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'&nbsp;'), ' ')
        .replaceAll(RegExp(r'&amp;'), '&')
        .replaceAll(RegExp(r'&lt;'), '<')
        .replaceAll(RegExp(r'&gt;'), '>')
        .replaceAll(RegExp(r'&quot;'), '"')
        .replaceAll(RegExp(r'&#[0-9]+;'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static DateTime _parseDate(String dateString) {
    try {
      // Tentar formatos comuns de RSS
      final formats = [
        DateFormat('EEE, dd MMM yyyy HH:mm:ss Z', 'en'),
        DateFormat('EEE, dd MMM yyyy HH:mm:ss', 'en'),
        DateFormat('yyyy-MM-ddTHH:mm:ssZ'),
        DateFormat('yyyy-MM-dd HH:mm:ss'),
        DateFormat('dd/MM/yyyy HH:mm:ss'),
        DateFormat('dd MMM yyyy HH:mm:ss', 'en'),
      ];

      for (var format in formats) {
        try {
          return format.parse(dateString);
        } catch (e) {
          continue;
        }
      }

      // Tentar formatos em português
      final ptFormats = [
        DateFormat('EEE, dd MMM yyyy HH:mm:ss Z', 'pt_BR'),
        DateFormat('dd/MM/yyyy HH:mm:ss', 'pt_BR'),
      ];

      for (var format in ptFormats) {
        try {
          return format.parse(dateString);
        } catch (e) {
          continue;
        }
      }

      return DateTime.now();
    } catch (e) {
      print('Erro ao parsear data: "$dateString" - $e');
      return DateTime.now();
    }
  }

  static int _calculateRelevance(String text) {
    final lowerText = text.toLowerCase();
    var score = 3;

    // Palavras-chave de alta relevância
    if (lowerText.contains('pcdf')) score += 4;
    if (lowerText.contains('polícia civil')) score += 4;
    if (lowerText.contains('distrito federal')) score += 2;
    if (lowerText.contains('df')) score += 1;

    // Palavras-chave de média relevância
    if (lowerText.contains('delegacia')) score += 2;
    if (lowerText.contains('operacao') || lowerText.contains('operação')) score += 2;
    if (lowerText.contains('prisao') || lowerText.contains('prisão')) score += 2;
    if (lowerText.contains('apreensao') || lowerText.contains('apreensão')) score += 2;
    if (lowerText.contains('investigação')) score += 2;

    // Termos gerais de segurança
    if (lowerText.contains('segurança')) score += 1;
    if (lowerText.contains('crime')) score += 1;
    if (lowerText.contains('policia') || lowerText.contains('polícia')) score += 1;

    return score.clamp(1, 10);
  }

  static int _calculateEngagement(String source) {
    final baseEngagement = {
      'G1 Distrito Federal': 5000,
      'Correio Braziliense': 4000,
      'Metrópoles DF': 3000,
      'Agência Brasil': 2000,
      'Jornal de Brasília': 1500,
      'Brasil 61': 1000,
      'R7 Distrito Federal': 1200,
      'UOL Notícias DF': 1800,
      'Google News': 1500,
      'CNN Brasil Segurança': 2000,
      'Terra Segurança': 1200,
    };
    return baseEngagement[source] ?? 500;
  }

  static String _extractPreview(String description) {
    final cleanDesc = _cleanHtml(description);
    return cleanDesc.length > 120
        ? cleanDesc.substring(0, 120) + '...'
        : cleanDesc;
  }

  static List<NewsArticle> _getFallbackNews() {
    // Notícias de fallback para quando a busca falha
    return [
      NewsArticle(
        id: 'fallback_1',
        title: 'PCDF realiza operação contra crime organizado no Distrito Federal',
        source: 'Sistema ALTOS',
        url: 'https://example.com',
        content: 'A Polícia Civil do Distrito Federal realizou uma operação para combater o crime organizado na região.',
        date: DateTime.now(),
        category: NewsCategory.pcdf,
        relevanceScore: 8,
        engagement: 1000,
        type: NewsType.portal,
        preview: 'Operação da PCDF no combate ao crime organizado...',
      ),
    ];
  }
}

// ========== WIDGETS (MANTIDOS IGUAIS) ==========

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
      'Jornal de Brasília': Colors.orange[600]!,
      'Brasil 61': Colors.red[600]!,
      'R7 Distrito Federal': Colors.orange[800]!,
      'UOL Notícias DF': Colors.blue[600]!,
      'CNN Brasil Segurança': Colors.red[800]!,
      'Terra Segurança': Colors.green[700]!,
      'Sistema ALTOS': Colors.blue[800]!,
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir o link'),
            backgroundColor: Colors.orange,
          ),
        );
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startMonitoring();
    });
  }

  void _initializeSources() {
    _sourcesSelection = {
      'G1 Distrito Federal': true,
      'Correio Braziliense': true,
      'Metrópoles DF': true,
      'Agência Brasil': true,
      'Jornal de Brasília': true,
      'Brasil 61': true,
      'R7 Distrito Federal': true,
      'UOL Notícias DF': true,
      'Google News': true,
      'CNN Brasil Segurança': true,
      'Terra Segurança': true,
    };
  }

  void _applyFilters() {
    List<NewsArticle> filtered = List.from(_articles);

    if (_startDate != null || _endDate != null) {
      filtered = filtered.where((article) {
        final articleDate = article.date;
        final start = _startDate ?? DateTime(1900);
        final end = _endDate ?? DateTime(2100);

        return articleDate.isAfter(start) && articleDate.isBefore(end);
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
        return article.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            article.content.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            article.source.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    setState(() {
      _filteredArticles = filtered;
    });
  }

  Future<void> _generateReport() async {
    if (_filteredArticles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma notícia para gerar relatório'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final totalNews = _filteredArticles.length;
      final highRelevance = _filteredArticles.where((a) => a.relevanceScore >= 8).length;
      final averageRelevance = _filteredArticles.where((a) => a.relevanceScore >= 5 && a.relevanceScore < 8).length;
      final lowRelevance = _filteredArticles.where((a) => a.relevanceScore < 5).length;

      final sourcesCount = <String, int>{};
      for (var article in _filteredArticles) {
        sourcesCount[article.source] = (sourcesCount[article.source] ?? 0) + 1;
      }

      final sourcesSummary = sourcesCount.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n');

      final reportContent = '''
RELATÓRIO PCDF CLIPPING - SISTEMA ALTOS

Data de geração: ${DateFormat('dd/MM/yyyy às HH:mm').format(DateTime.now())}
Período: ${_startDate != null ? DateFormat('dd/MM/yyyy').format(_startDate!) : 'Início'} à ${_endDate != null ? DateFormat('dd/MM/yyyy').format(_endDate!) : 'Fim'}

RESUMO ESTATÍSTICO:
- Total de notícias: $totalNews
- Alta relevância: $highRelevance
- Média relevância: $averageRelevance
- Baixa relevância: $lowRelevance

DISTRIBUIÇÃO POR FONTE:
$sourcesSummary

DETALHAMENTO DAS NOTÍCIAS:

${_filteredArticles.map((article) {
        return '''
📰 ${article.title}
   Fonte: ${article.source}
   Data: ${article.formattedDateTime}
   Relevância: ${article.relevanceScore}/10
   Engajamento: ${article.engagementFormatted}
   URL: ${article.url}
   ${'-' * 50}''';
      }).join('\n\n')}

Este relatório foi gerado automaticamente pelo Sistema ALTOS de Monitoramento.
      ''';

      await Share.share(
        reportContent,
        subject: 'Relatório PCDF Clipping - ${DateFormat('dd_MM_yyyy').format(DateTime.now())}',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Relatório gerado e compartilhado com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao gerar relatório: $e'),
          backgroundColor: Colors.red,
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
                  _searchQuery = value;
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
              Text('📅 ${article.formattedDateTime}'),
              Text('⭐ Score: ${article.relevanceScore} - ${article.relevanceText}'),
              Text('👁️ Engajamento: ${article.engagementFormatted}'),
              Text('🔗 Tipo: ${_getTypeText(article.type)}'),
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
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              Share.share(
                'Confira esta notícia: ${article.title}\n\n${article.url}',
                subject: 'Notícia PCDF Clipping',
              );
            },
          ),
        ],
      ),
    );
  }

  String _getTypeText(NewsType type) {
    switch (type) {
      case NewsType.jornal: return 'Jornal';
      case NewsType.portal: return 'Portal';
      case NewsType.social: return 'Rede Social';
      case NewsType.agencia: return 'Agência';
      case NewsType.video: return 'Vídeo';
    }
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
        count: 50,
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

      print('Busca concluída: ${newArticles.length} notícias encontradas');

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