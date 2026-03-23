import 'package:flutter/material.dart';
import '../services/socket_service.dart';
import '../services/api_service.dart';

class ConfidenceScoreWidget extends StatefulWidget {
  final String productName;
  final double proposedPrice;
  final int initialScore;
  final Map<String, dynamic> initialBreakdown;

  const ConfidenceScoreWidget({
    super.key,
    required this.productName,
    required this.proposedPrice,
    required this.initialScore,
    required this.initialBreakdown,
  });

  @override
  State<ConfidenceScoreWidget> createState() => _ConfidenceScoreWidgetState();
}

class _ConfidenceScoreWidgetState extends State<ConfidenceScoreWidget> {
  final SocketService _socketService = SocketService();
  final ApiService _apiService = ApiService();
  late int _currentScore;
  late Map<String, dynamic> _currentBreakdown;
  bool _isInteracting = false;

  @override
  void initState() {
    super.initState();
    _currentScore = widget.initialScore;
    _currentBreakdown = widget.initialBreakdown;

    // Listen selectively to real-time score updates
    _socketService.onProductScoreUpdated('score_${widget.productName}', (data) {
      if (mounted && data != null && data['product_name'] == widget.productName) {
        _silentRefreshScore();
      }
    });
  }

  @override
  void dispose() {
    // Only remove specific listeners if scoped, otherwise rely on general cleanup
    _socketService.offProductScoreUpdated('score_${widget.productName}');
    super.dispose();
  }

  Future<void> _silentRefreshScore() async {
    try {
      final data = await _apiService.getProductConfidence(widget.productName, widget.proposedPrice);
      if (mounted) {
        setState(() {
          _currentScore = data['score'] ?? _currentScore;
          _currentBreakdown = data['breakdown'] ?? _currentBreakdown;
        });
      }
    } catch (e) {
      debugPrint('Score sync error: $e');
    }
  }

  void _showInteractionModal() {
    final reviewController = TextEditingController();
    double rating = 5.0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: Text('Rate "${widget.productName}"'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Help the community by providing your intelligence on this product to train the AI.'),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      icon: Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 32,
                      ),
                      onPressed: () {
                        setModalState(() => rating = index + 1.0);
                      },
                    );
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reviewController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Add a written review (powers AI sentiment)...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F264D), foregroundColor: Colors.white),
                onPressed: _isInteracting ? null : () async {
                  setState(() => _isInteracting = true);
                  setModalState(() {});
                  try {
                    await _apiService.interactWithProduct(
                      widget.productName,
                      review: reviewController.text.trim(),
                      voteVal: rating,
                    );
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Interaction recorded! Recalculating score...')),
                      );
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _isInteracting = false);
                  }
                },
                child: _isInteracting 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                  : const Text('Submit'),
              ),
            ],
          );
        }
      ),
    );
  }

  Color _getScoreColor(int s) {
    if (s >= 80) return Colors.green;
    if (s >= 50) return Colors.amber.shade600;
    return Colors.red;
  }

  String _getRecommendationText(int s) {
    if (s >= 80) return "Highly Recommended";
    if (s >= 50) return "Moderate";
    return "Risky";
  }

  @override
  Widget build(BuildContext context) {
    final scoreColor = _getScoreColor(_currentScore);
    final recommendation = _getRecommendationText(_currentScore);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'AI Confidence Score',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F264D),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add_reaction_outlined, size: 18),
                  label: const Text('Rate'),
                  onPressed: _showInteractionModal,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF1D5DE4),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                )
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: _currentScore / 100,
                        strokeWidth: 10,
                        backgroundColor: Colors.grey.shade100,
                        valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                        strokeCap: StrokeCap.round,
                      ),
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$_currentScore%',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: scoreColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recommendation,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: scoreColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Live sync enabled. Add reviews to dynamically train the AI analysis model.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(height: 1),
            const SizedBox(height: 16),
            const Text(
              'Real-Time Breakdown (Cached)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMetricItem('Rating', '⭐', _currentBreakdown['rating_score'] ?? 0),
                _buildMetricItem('Sentiment', '💬', _currentBreakdown['sentiment_score'] ?? 0),
                _buildMetricItem('Popularity', '🔥', _currentBreakdown['popularity_score'] ?? 0),
                _buildMetricItem('Price', '💰', _currentBreakdown['price_score'] ?? 0),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricItem(String label, String emoji, dynamic value) {
    double progress = (value is num ? value.toDouble() : 0.0) / 100.0;
    if (progress > 1.0) progress = 1.0;
    if (progress < 0.0) progress = 0.0;

    final metricColor = _getScoreColor((progress * 100).toInt());

    return Expanded(
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: metricColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
