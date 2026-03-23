const { analyzeReviews } = require('./ai_sentiment');

/**
 * Calculates the product confidence score.
 * 
 * Formula:
 * Confidence Score =
 * (0.4 * rating_score) +
 * (0.3 * sentiment_score) +
 * (0.2 * popularity_score) +
 * (0.1 * price_score)
 * 
 * @param {Object} product - Product details from global_products
 * @param {number} proposedPrice - The price the user is evaluating
 * @returns {Object} { score: number, breakdown: Object }
 */
async function calculateConfidence(product, proposedPrice) {
    const { rating = 0, number_of_votes = 0, average_price = 0, reviews = [] } = product;

    // 1. Rating Score (40% weight) - Input: 0-5
    const ratingScore = (rating / 5) * 100;

    // 2. Sentiment Score (30% weight) - Powered by OpenAI / lightweight local fallback
    const sentimentAnalysis = await analyzeReviews(reviews);
    const sentimentScore = sentimentAnalysis.score;

    // 3. Popularity Score (20% weight) - Normalized votes
    // We assume 100+ votes is very popular (100 score).
    let popularityScore = (number_of_votes / 100) * 100;
    if (popularityScore > 100) popularityScore = 100;

    // 4. Price Score (10% weight)
    // If proposedPrice < averagePrice -> higher score
    let priceScore = 50; // Default if average_price is 0
    if (average_price > 0 && proposedPrice > 0) {
        const ratio = proposedPrice / average_price;
        // If ratio = 1 (same price) -> 50 score
        // If ratio = 0.5 (half price) -> 100 score
        // If ratio = 1.5 (50% more expensive) -> 0 score
        priceScore = 100 - ((ratio - 0.5) * 100);
        if (priceScore > 100) priceScore = 100;
        if (priceScore < 0) priceScore = 0;
    }

    const finalScore = 
        (0.4 * ratingScore) +
        (0.3 * sentimentScore) +
        (0.2 * popularityScore) +
        (0.1 * priceScore);

    return {
        score: Math.round(finalScore),
        breakdown: {
            rating_score: Math.round(ratingScore),
            sentiment_score: Math.round(sentimentScore),
            sentiment_details: {
                positive_percentage: sentimentAnalysis.positive_percentage,
                negative_percentage: sentimentAnalysis.negative_percentage,
                score: sentimentAnalysis.score
            },
            popularity_score: Math.round(popularityScore),
            price_score: Math.round(priceScore)
        }
    };
}

module.exports = { calculateConfidence };
