import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import 'dart:convert';
//import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const PCDFClippingApp());
}

// ========== CONFIGURAÇÕES ==========
const GOOGLE_API_KEY = 'SUA_CHAVE_API_GOOGLE'; // Substitua pela sua chave
const GOOGLE_SEARCH_ENGINE_ID = 'SEU_ID_MOTOR_BUSCA'; // Substitua pelo seu ID

// ========== MODELOS ==========
enum NewsCategory { pcdf, policia, seguranca, justica, geral, operacao }
enum NewsType { jornal, portal, social, agencia, video, google }

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
  final String? imageUrl;

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
    this.imageUrl,
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
      'imageUrl': imageUrl,
      'isRead': isRead,
    };
  }
}

// ========== SERVIÇOS DE BUSCA ==========
class NewsSearchService {
  static final List<NewsSource> _newsSources = [
    NewsSource(
      name: 'G1 Distrito Federal',
      rss: 'https://g1.globo.com/rss/g1/distrito-federal/',
      type: NewsType.portal,
      weight: 10,
      category: NewsCategory.pcdf,
    ),
    NewsSource(
      name: 'Correio Braziliense',
      rss: 'https://www.correiobraziliense.com.br/rss',
      type: NewsType.jornal,
      weight: 9,
      category: NewsCategory.geral,
    ),
    NewsSource(
      name: 'Metrópoles DF',
      rss: 'https://www.metropoles.com/feed',
      type: NewsType.portal,
      weight: 8,
      category: NewsCategory.pcdf,
    ),
    NewsSource(
      name: 'Agência Brasil',
      rss: 'https://agenciabrasil.ebc.com.br/rss/ultimasnoticias/feed.xml',
      type: NewsType.agencia,
      weight: 7,
      category: NewsCategory.geral,
    ),
    NewsSource(
      name: 'Jornal de Brasília',
      rss: 'https://www.jornaldebrasilia.com.br/feed/',
      type: NewsType.jornal,
      weight: 6,
      category: NewsCategory.pcdf,
    ),
  ];

  static final List<String> _pcdfKeywords = [
    'pcdf', 'polícia civil', 'polícia civil df', 'polícia civil distrito federal',
    'delegacia', 'delegado', 'investigação', 'inquérito', 'prisão', 'prisao',
    'operacao', 'operação', 'apreensão', 'apreensao', 'flagrante', 'mandado',
    'crime', 'criminal', 'segurança pública', 'seguranca publica', 'df',
    'delegado de polícia', 'investigador', 'perícia', 'prova', 'testemunha',
    'acusado', 'suspeito', 'vítima', 'homícidio', 'roubo', 'furto', 'tráfico'
  ];

  static Future<List<NewsArticle>> searchComprehensiveNews({
    int count = 50,
    DateTime? startDate,
    DateTime? endDate,
    bool useGoogleSearch = true,
  }) async {
    final results = <NewsArticle>[];

    try {
      print('Iniciando busca abrangente de notícias...');

      // Buscar de fontes RSS
      final rssResults = await _fetchAllRSSFeeds(startDate: startDate, endDate: endDate);
      results.addAll(rssResults);
      print('RSS: ${rssResults.length} notícias');

      // Buscar do Google (se habilitado)
      if (useGoogleSearch) {
        try {
          final googleResults = await GoogleSearchService.searchPCDFNews(
            startDate: startDate,
            endDate: endDate,
            maxResults: 20,
          );
          results.addAll(googleResults);
          print('Google: ${googleResults.length} notícias');
        } catch (e) {
          print('Erro na busca do Google: $e');
        }
      }

      // Processar e filtrar resultados
      final processedResults = await _processAndFilterResults(results, count);
      print('Resultados finais: ${processedResults.length} notícias');

      return processedResults;

    } catch (e) {
      print('Erro geral na busca: $e');
      return [];
    }
  }

  static Future<List<NewsArticle>> _fetchAllRSSFeeds({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final results = <NewsArticle>[];
    final futures = <Future<List<NewsArticle>>>[];

    for (var source in _newsSources) {
      futures.add(_fetchRSSFeed(source, startDate: startDate, endDate: endDate));
    }

    final allResults = await Future.wait(futures);
    for (var result in allResults) {
      results.addAll(result);
    }

    return _removeDuplicates(results);
  }

  static Future<List<NewsArticle>> _fetchRSSFeed(
      NewsSource source, {
        DateTime? startDate,
        DateTime? endDate,
      }) async {
    final results = <NewsArticle>[];

    try {
      final response = await http.get(
        Uri.parse(source.rss),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'application/rss+xml, text/xml, */*',
        },
      );

      if (response.statusCode == 200) {
        final document = xml.XmlDocument.parse(response.body);
        final items = document.findAllElements('item').take(20);

        for (var item in items) {
          try {
            final article = await _parseRSSItem(item, source);
            if (article != null) {
              // Filtrar por data
              if (startDate != null && article.date.isBefore(startDate)) continue;
              if (endDate != null && article.date.isAfter(endDate)) continue;

              results.add(article);
            }
          } catch (e) {
            print('Erro ao processar item RSS: $e');
          }
        }
      }
    } catch (e) {
      print('Erro no RSS ${source.name}: $e');
    }

    return results;
  }

  static Future<NewsArticle?> _parseRSSItem(xml.XmlElement item, NewsSource source) async {
    try {
      final title = item.findElements('title').firstOrNull?.text ?? 'Sem título';
      final link = item.findElements('link').firstOrNull?.text ?? '';
      final pubDate = item.findElements('pubDate').firstOrNull?.text ?? '';
      final description = item.findElements('description').firstOrNull?.text ?? '';
      final content = item.findElements('content:encoded').firstOrNull?.text ?? description;

      // Tentar encontrar imagem
      final imageUrl = item.findElements('enclosure').firstOrNull?.getAttribute('url') ??
          item.findElements('media:content').firstOrNull?.getAttribute('url');

      if (title == 'Sem título' || link.isEmpty) return null;

      final articleDate = _parseDate(pubDate);
      final cleanTitle = _cleanHtml(title);
      final cleanContent = _cleanHtml(content);

      // Calcular relevância para PCDF
      final relevanceScore = _calculateRelevance(cleanTitle + cleanContent);

      // Se relevância muito baixa, pular
      if (relevanceScore < 3) return null;

      return NewsArticle(
        id: '${source.name}_${link.hashCode}',
        title: cleanTitle,
        source: source.name,
        url: link,
        content: cleanContent,
        date: articleDate,
        category: _determineCategory(cleanTitle + cleanContent),
        relevanceScore: relevanceScore,
        engagement: _calculateEngagement(source.name),
        type: source.type,
        preview: _extractPreview(cleanContent),
        imageUrl: imageUrl,
      );
    } catch (e) {
      print('Erro no parse do item: $e');
      return null;
    }
  }

  static Future<List<NewsArticle>> _processAndFilterResults(List<NewsArticle> articles, int maxCount) async {
    // Remover duplicatas
    var uniqueArticles = _removeDuplicates(articles);

    // Ordenar por relevância e data
    uniqueArticles.sort((a, b) {
      final relevanceCompare = b.relevanceScore.compareTo(a.relevanceScore);
      if (relevanceCompare != 0) return relevanceCompare;
      return b.date.compareTo(a.date);
    });

    // Manter apenas as mais relevantes
    return uniqueArticles.take(maxCount).toList();
  }

  // ========== MÉTODOS AUXILIARES ==========
  static String _cleanHtml(String htmlString) {
    return htmlString
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'&nbsp;'), ' ')
        .replaceAll(RegExp(r'&amp;'), '&')
        .replaceAll(RegExp(r'&quot;'), '"')
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

      return DateTime.now().subtract(const Duration(days: 365)); // Data antiga se não conseguir parsear
    } catch (e) {
      return DateTime.now().subtract(const Duration(days: 365));
    }
  }

  static int _calculateRelevance(String text) {
    final lowerText = text.toLowerCase();
    var score = 0;

    // Palavras-chave principais (alto peso)
    if (lowerText.contains('pcdf')) score += 5;
    if (lowerText.contains('polícia civil')) score += 5;
    if (lowerText.contains('delegado')) score += 4;
    if (lowerText.contains('delegacia')) score += 4;
    if (lowerText.contains('investigação')) score += 4;

    // Palavras-chave secundárias (médio peso)
    if (lowerText.contains('operação')) score += 3;
    if (lowerText.contains('prisão')) score += 3;
    if (lowerText.contains('apreensão')) score += 3;
    if (lowerText.contains('inquérito')) score += 3;

    // Palavras-chave terciárias (baixo peso)
    if (lowerText.contains('df')) score += 1;
    if (lowerText.contains('distrito federal')) score += 2;
    if (lowerText.contains('brasília')) score += 1;
    if (lowerText.contains('crime')) score += 2;
    if (lowerText.contains('segurança')) score += 1;

    return score.clamp(1, 10);
  }

  static int _calculateEngagement(String source) {
    final engagementMap = {
      'G1 Distrito Federal': 8500,
      'Correio Braziliense': 7200,
      'Metrópoles DF': 6800,
      'Agência Brasil': 4500,
      'Jornal de Brasília': 3800,
      'Google News': 5000,
    };
    return engagementMap[source] ?? 1000;
  }

  static String _extractPreview(String content) {
    final cleanContent = content.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ');
    return cleanContent.length > 150 ? cleanContent.substring(0, 150) + '...' : cleanContent;
  }

  static NewsCategory _determineCategory(String text) {
    final lowerText = text.toLowerCase();
    if (lowerText.contains('pcdf') || lowerText.contains('polícia civil')) {
      return NewsCategory.pcdf;
    } else if (lowerText.contains('operação') || lowerText.contains('prisão')) {
      return NewsCategory.operacao;
    } else if (lowerText.contains('segurança')) {
      return NewsCategory.seguranca;
    } else if (lowerText.contains('justiça') || lowerText.contains('judiciário')) {
      return NewsCategory.justica;
    } else {
      return NewsCategory.geral;
    }
  }

  static List<NewsArticle> _removeDuplicates(List<NewsArticle> articles) {
    final seenUrls = <String>{};
    final uniqueArticles = <NewsArticle>[];

    for (var article in articles) {
      final normalizedUrl = article.url.split('?').first; // Remover parâmetros de URL
      if (!seenUrls.contains(normalizedUrl)) {
        seenUrls.add(normalizedUrl);
        uniqueArticles.add(article);
      }
    }

    return uniqueArticles;
  }
}

class NewsSource {
  final String name;
  final String rss;
  final NewsType type;
  final int weight;
  final NewsCategory category;

  NewsSource({
    required this.name,
    required this.rss,
    required this.type,
    required this.weight,
    required this.category,
  });
}

// ========== SERVIÇO DE BUSCA DO GOOGLE ==========
class GoogleSearchService {
  static Future<List<NewsArticle>> searchPCDFNews({
    DateTime? startDate,
    DateTime? endDate,
    int maxResults = 20,
  }) async {
    final results = <NewsArticle>[];

    try {
      // Consultas de busca otimizadas para PCDF
      final queries = [
        'PCDF Polícia Civil Distrito Federal notícias',
        'delegado DF investigação',
        'operação policial Brasília',
        'prisão delegacia Distrito Federal',
        'polícia civil apreensão DF',
      ];

      for (var query in queries) {
        try {
          final news = await _googleSearch(query, maxResults: 5);
          results.addAll(news);
          await Future.delayed(const Duration(seconds: 1)); // Rate limiting
        } catch (e) {
          print('Erro na query "$query": $e');
        }
      }

      // Filtrar por data se especificado
      if (startDate != null || endDate != null) {
        results.retainWhere((article) {
          if (startDate != null && article.date.isBefore(startDate)) return false;
          if (endDate != null && article.date.isAfter(endDate)) return false;
          return true;
        });
      }

      return results;

    } catch (e) {
      print('Erro na busca do Google: $e');
      return [];
    }
  }

  static Future<List<NewsArticle>> _googleSearch(String query, {int maxResults = 10}) async {
    final results = <NewsArticle>[];

    try {
      // Implementação simplificada - em produção usar pacote oficial do Google
      final searchUrl = Uri.parse(
          'https://www.googleapis.com/customsearch/v1?'
              'key=$GOOGLE_API_KEY&'
              'cx=$GOOGLE_SEARCH_ENGINE_ID&'
              'q=${Uri.encodeQueryComponent(query)}&'
              'num=$maxResults&'
              'sort=date&'
              'lr=lang_pt'
      );

      final response = await http.get(searchUrl);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List?;

        if (items != null) {
          for (var item in items) {
            try {
              final article = _parseGoogleResult(item, query);
              if (article != null) {
                results.add(article);
              }
            } catch (e) {
              print('Erro ao processar resultado Google: $e');
            }
          }
        }
      }
    } catch (e) {
      print('Erro na API Google: $e');
    }

    return results;
  }

  static NewsArticle? _parseGoogleResult(Map<String, dynamic> item, String query) {
    try {
      final title = item['title'] ?? '';
      final link = item['link'] ?? '';
      final snippet = item['snippet'] ?? '';
      final displayLink = item['displayLink'] ?? 'Google';

      if (title.isEmpty || link.isEmpty) return null;

      // Calcular relevância
      final relevanceScore = _calculateGoogleRelevance(title + snippet, query);

      return NewsArticle(
        id: 'google_${link.hashCode}',
        title: _cleanText(title),
        source: displayLink,
        url: link,
        content: snippet,
        date: DateTime.now(), // Google não retorna data facilmente
        category: NewsCategory.pcdf,
        relevanceScore: relevanceScore,
        engagement: 5000, // Engajamento padrão para Google
        type: NewsType.google,
        preview: snippet,
      );
    } catch (e) {
      print('Erro no parse do Google: $e');
      return null;
    }
  }

  static int _calculateGoogleRelevance(String text, String query) {
    var score = NewsSearchService._calculateRelevance(text);

    // Bonus por correspondência com a query
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    if (lowerText.contains(lowerQuery)) score += 2;
    if (lowerText.contains('pcdf') && lowerText.contains('df')) score += 3;

    return score.clamp(1, 10);
  }

  static String _cleanText(String text) {
    return text.replaceAll('<b>', '').replaceAll('</b>', '').trim();
  }
}

// ========== WIDGETS ATUALIZADOS ==========
class NewsItemWidget extends StatelessWidget {
  final NewsArticle article;
  final VoidCallback? onTap;
  final VoidCallback? onShare;

  const NewsItemWidget({
    Key? key,
    required this.article,
    this.onTap,
    this.onShare,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabeçalho com fonte e data
              Row(
                children: [
                  _buildSourceChip(article.source),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        article.formattedDate,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
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
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 8),

              // Preview
              if (article.preview != null && article.preview!.isNotEmpty) ...[
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

              // Rodapé com métricas e ações
              Row(
                children: [
                  // Relevância
                  _buildRelevanceChip(article.relevanceScore),

                  const SizedBox(width: 8),

                  // Engajamento
                  _buildEngagementChip(article.engagement),

                  const Spacer(),

                  // Ações
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.share, size: 20),
                        onPressed: onShare,
                        color: Colors.grey[600],
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => _launchUrl(article.url, context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1a365d),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text('Abrir', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceChip(String source) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _getSourceColor(source),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        source.length > 20 ? '${source.substring(0, 20)}...' : source,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildRelevanceChip(int score) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getScoreColor(score),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            '$score',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEngagementChip(int engagement) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.visibility, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          article.engagementFormatted,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Color _getSourceColor(String source) {
    final colors = {
      'G1 Distrito Federal': Colors.red[700]!,
      'Correio Braziliense': Colors.blue[700]!,
      'Metrópoles DF': Colors.purple[600]!,
      'Agência Brasil': Colors.green[600]!,
      'Jornal de Brasília': Colors.orange[600]!,
      'Google News': Colors.blue[800]!,
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

class EnhancedControlPanel extends StatelessWidget {
  final bool isMonitoring;
  final int articleCount;
  final DateTime lastUpdate;
  final bool useGoogleSearch;
  final VoidCallback onRefresh;
  final VoidCallback onGenerateReport;
  final ValueChanged<bool> onGoogleSearchChanged;

  const EnhancedControlPanel({
    Key? key,
    required this.isMonitoring,
    required this.articleCount,
    required this.lastUpdate,
    required this.useGoogleSearch,
    required this.onRefresh,
    required this.onGenerateReport,
    required this.onGoogleSearchChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Status e estatísticas
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: isMonitoring ? Colors.green : Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Status: ${isMonitoring ? 'ATIVO' : 'INATIVO'}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isMonitoring ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '📰 Notícias encontradas: $articleCount',
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      Text(
                        '🕒 Última atualização: ${DateFormat('dd/MM/yyyy HH:mm').format(lastUpdate)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Atualizar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1a365d),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Configurações
            Row(
              children: [
                const Text('Busca do Google:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(width: 8),
                Switch(
                  value: useGoogleSearch,
                  onChanged: onGoogleSearchChanged,
                  activeColor: const Color(0xFF1a365d),
                ),
                const Spacer(),
                Text(
                  useGoogleSearch ? 'Ativada' : 'Desativada',
                  style: TextStyle(
                    color: useGoogleSearch ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Botão de relatório
            ElevatedButton.icon(
              onPressed: onGenerateReport,
              icon: const Icon(Icons.analytics),
              label: const Text('Gerar Relatório Completo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1a365d),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdvancedDateFilter extends StatefulWidget {
  final DateTime? startDate;
  final DateTime? endDate;
  final Function(DateTime?, DateTime?) onDateChanged;

  const AdvancedDateFilter({
    Key? key,
    required this.startDate,
    required this.endDate,
    required this.onDateChanged,
  }) : super(key: key);

  @override
  _AdvancedDateFilterState createState() => _AdvancedDateFilterState();
}

class _AdvancedDateFilterState extends State<AdvancedDateFilter> {
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

  void _setQuickFilter(int days) {
    final endDate = DateTime.now();
    final startDate = endDate.subtract(Duration(days: days));
    widget.onDateChanged(startDate, endDate);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🔍 Filtros de Data',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),

            // Filtros rápidos
            const Text('Filtros rápidos:', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _buildQuickFilterButton('24h', 1),
                _buildQuickFilterButton('7d', 7),
                _buildQuickFilterButton('30d', 30),
                _buildQuickFilterButton('90d', 90),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // Filtros customizados
            const Text('Filtro personalizado:', style: TextStyle(fontWeight: FontWeight.w500)),
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
                          minimumSize: const Size(double.infinity, 40),
                        ),
                        child: Text(
                          widget.startDate != null
                              ? DateFormat('dd/MM/yyyy').format(widget.startDate!)
                              : 'Selecionar',
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
                          minimumSize: const Size(double.infinity, 40),
                        ),
                        child: Text(
                          widget.endDate != null
                              ? DateFormat('dd/MM/yyyy').format(widget.endDate!)
                              : 'Selecionar',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (widget.startDate != null || widget.endDate != null) ...[
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _clearDates,
                child: const Text('Limpar Filtros'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickFilterButton(String label, int days) {
    return OutlinedButton(
      onPressed: () => _setQuickFilter(days),
      child: Text(label),
    );
  }
}

// ========== PÁGINA PRINCIPAL ATUALIZADA ==========
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
  bool _useGoogleSearch = true;

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
      final newArticles = await NewsSearchService.searchComprehensiveNews(
        startDate: _startDate,
        endDate: _endDate,
        useGoogleSearch: _useGoogleSearch,
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
      _showError('Erro ao carregar notícias: $e');
    }
  }

  void _applyFilters() {
    List<NewsArticle> filtered = List.from(_articles);

    // Filtro de data
    if (_startDate != null || _endDate != null) {
      filtered = filtered.where((article) {
        final start = _startDate ?? DateTime(1900);
        final end = _endDate ?? DateTime(2100);
        return article.date.isAfter(start) && article.date.isBefore(end);
      }).toList();
    }

    // Filtro de busca
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
      _showError('Nenhuma notícia para gerar relatório');
      return;
    }

    try {
      final reportContent = StringBuffer()
        ..writeln('RELATÓRIO PCDF CLIPPING - SISTEMA AVANÇADO')
        ..writeln('=' * 50)
        ..writeln('Data: ${DateFormat('dd/MM/yyyy às HH:mm').format(DateTime.now())}')
        ..writeln('Período: ${_startDate != null ? DateFormat('dd/MM/yyyy').format(_startDate!) : "Início"} à ${_endDate != null ? DateFormat('dd/MM/yyyy').format(_endDate!) : "Fim"}')
        ..writeln('Total de notícias: ${_filteredArticles.length}')
        ..writeln('Busca do Google: ${_useGoogleSearch ? "Ativa" : "Inativa"}')
        ..writeln()
        ..writeln('DETALHES DAS NOTÍCIAS:')
        ..writeln('=' * 50);

      // Agrupar por categoria
      final articlesByCategory = <NewsCategory, List<NewsArticle>>{};
      for (var article in _filteredArticles) {
        articlesByCategory.putIfAbsent(article.category, () => []).add(article);
      }

      for (var category in articlesByCategory.keys) {
        reportContent.writeln(
          '\n${category.toString().split('.').last.toUpperCase()}:',
        );

        for (var article in articlesByCategory[category]!) {
          reportContent.writeln('📌 ${article.title}');
          reportContent.writeln('   📊 Relevância: ${article.relevanceScore}/10');
          reportContent.writeln('   📍 Fonte: ${article.source}');
          reportContent.writeln('   📅 Data: ${article.formattedDateTime}');
          reportContent.writeln('   🔗 URL: ${article.url}');
          reportContent.writeln('   ${'-' * 40}');
        }
      }

      // Estatísticas
      reportContent
        ..writeln('\nESTATÍSTICAS:')
        ..writeln('=' * 50)
        ..writeln('Média de relevância: ${_calculateAverageRelevance().toStringAsFixed(1)}/10')
        ..writeln('Notícias de alta relevância: ${_filteredArticles.where((a) => a.relevanceScore >= 8).length}')
        ..writeln('Fontes únicas: ${_filteredArticles.map((a) => a.source).toSet().length}');

      await Share.share(reportContent.toString());
    } catch (e) {
      _showError('Erro ao gerar relatório: $e');
    }
  }

  double _calculateAverageRelevance() {
    if (_filteredArticles.isEmpty) return 0;
    return _filteredArticles.map((a) => a.relevanceScore).reduce((a, b) => a + b) / _filteredArticles.length;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showArticleDetails(NewsArticle article) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      article.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  _buildDetailChip('Fonte: ${article.source}', Icons.source),
                  _buildDetailChip(article.formattedDateTime, Icons.calendar_today),
                  _buildDetailChip('Relevância: ${article.relevanceScore}/10', Icons.star),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Conteúdo:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(article.content),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _launchUrl(article.url),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Abrir Notícia'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _shareArticle(article),
                    icon: const Icon(Icons.share),
                    label: const Text('Compartilhar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailChip(String text, IconData icon) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _showError('Erro ao abrir link: $e');
    }
  }

  Future<void> _shareArticle(NewsArticle article) async {
    try {
      await Share.share(
        '${article.title}\n\nFonte: ${article.source}\nData: ${article.formattedDateTime}\n\n${article.url}',
      );
    } catch (e) {
      _showError('Erro ao compartilhar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PCDF Clipping Avançado'),
            Text('Sistema de Monitoramento Inteligente', style: TextStyle(fontSize: 12)),
          ],
        ),
        backgroundColor: const Color(0xFF1a365d),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showAppInfo(),
          ),
        ],
      ),
      body: Column(
        children: [
          EnhancedControlPanel(
            isMonitoring: true,
            articleCount: _filteredArticles.length,
            lastUpdate: _lastUpdate,
            useGoogleSearch: _useGoogleSearch,
            onRefresh: _loadNews,
            onGenerateReport: _generateReport,
            onGoogleSearchChanged: (value) {
              setState(() {
                _useGoogleSearch = value;
              });
              _loadNews();
            },
          ),
          AdvancedDateFilter(
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
              decoration: InputDecoration(
                hintText: '🔍 Buscar notícias...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      _searchQuery = '';
                    });
                    _applyFilters();
                  },
                ) : null,
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loadNews,
        icon: const Icon(Icons.refresh),
        label: const Text('Atualizar'),
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
            SizedBox(height: 8),
            Text('Isso pode levar alguns instantes', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
    }

    if (_filteredArticles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('Nenhuma notícia encontrada'),
            const SizedBox(height: 8),
            Text(
              'Tente ajustar os filtros ou atualizar a busca',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
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
          onShare: () => _shareArticle(article),
        );
      },
    );
  }

  void _showAppInfo() {
    showAboutDialog(
      context: context,
      applicationName: 'PCDF Clipping Avançado',
      applicationVersion: '2.0.0',
      applicationIcon: const Icon(Icons.security, color: Color(0xFF1a365d)),
      children: [
        const Text('Sistema inteligente de monitoramento de notícias para a Polícia Civil do DF.'),
        const SizedBox(height: 8),
        const Text('Recursos:'),
        const Text('• Busca em tempo real em múltiplas fontes'),
        const Text('• Integração com Google Search'),
        const Text('• Análise de relevância automática'),
        const Text('• Geração de relatórios detalhados'),
      ],
    );
  }
}

class PCDFClippingApp extends StatelessWidget {
  const PCDFClippingApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PCDF Clipping Avançado',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1a365d),
          foregroundColor: Colors.white,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}