const Sentiment = require('sentiment');
const localSentiment = new Sentiment();

/**
 * Analyzes a batch of product reviews using OpenAI (if available) or a local lightweight model.
 * 
 * @param {string[]} reviews Array of text reviews
 * @returns {Promise<{positive_percentage: number, negative_percentage: number, score: number}>}
 */
async function analyzeReviews(reviews) {
    // 1. Handle empty reviews
    if (!reviews || reviews.length === 0) {
        return { positive_percentage: 0, negative_percentage: 0, score: 50 };
    }

    // 2. Use OpenAI API if Key is provided
    if (process.env.OPENAI_API_KEY) {
        try {
            // Using Node 18+ global fetch
            const response = await fetch('https://api.openai.com/v1/chat/completions', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
                },
                body: JSON.stringify({
                    model: 'gpt-3.5-turbo', // Low cost model
                    messages: [
                        { 
                            role: 'system', 
                            content: 'You are a concise JSON sentiment analyzer. You evaluate a list of product reviews and return ONLY valid JSON in this exact format, with no markdown code blocks: {"positive_percentage": 0, "negative_percentage": 0, "score": 0}. Score is 0-100 indicating overall sentiment.' 
                        },
                        { 
                            role: 'user', 
                            content: `Analyze the overall sentiment of these product reviews:\n${reviews.map(r => "- " + r).join('\n')}` 
                        }
                    ],
                    temperature: 0.1,
                    max_tokens: 150
                })
            });

            if (response.ok) {
                const data = await response.json();
                let content = data.choices[0].message.content.trim();
                
                // Remove potential markdown wrappers if the AI hallucinates them despite instructions
                if (content.startsWith('```json')) {
                    content = content.replace(/^```json\n/, '').replace(/\n```$/, '');
                }

                const parsed = JSON.parse(content);
                return {
                    positive_percentage: parsed.positive_percentage || 0,
                    negative_percentage: parsed.negative_percentage || 0,
                    score: parsed.score !== undefined ? parsed.score : 50
                };
            } else {
                const errText = await response.text();
                console.warn('OpenAI API request failed, falling back to local lightweight model.', errText);
            }
        } catch (error) {
            console.warn('Failed to parse OpenAI response, using fallback.', error.message);
        }
    }

    // 3. Fallback: Local Lightweight NLP Model (Zero-cost, extremely fast)
    let positiveCount = 0;
    let negativeCount = 0;
    let totalScore = 0;

    reviews.forEach(review => {
        const result = localSentiment.analyze(review);
        
        if (result.score > 0) positiveCount++;
        if (result.score < 0) negativeCount++;

        // Map comparative score (-5 to 5) to 0-100 scale
        let mapped = 50 + (result.comparative * 25);
        if (mapped > 100) mapped = 100;
        if (mapped < 0) mapped = 0;
        totalScore += mapped;
    });

    const totalReviews = reviews.length;
    return {
        positive_percentage: Math.round((positiveCount / totalReviews) * 100),
        negative_percentage: Math.round((negativeCount / totalReviews) * 100),
        score: Math.round(totalScore / totalReviews)
    };
}

module.exports = { analyzeReviews };
