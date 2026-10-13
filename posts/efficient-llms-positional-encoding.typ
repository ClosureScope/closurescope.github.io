#import "../typst/template.typ": *
#show: article.with(
  title: "Efficient LLMs: Positional Encoding",
  date: "2026-10-11",
  category: "LLM",
)

= Sinusoidal Absolute Position Embedding

The original Transformer adds sinusoidal features to the token embedding:

$ "PE"_(p, 2 i) = sin(p / 10000^((2 i) / d)) $
$ "PE"_(p, 2 i + 1) = cos(p / 10000^((2 i) / d)) $

*Remark:* Simple and parallelizable, but fails to model relative distances and long-context behavior beyond the trained range is not guaranteed.


= Shaw-style Relative Position Encoding

Add learned, clipped relative-position vectors to both keys and values.

For token positions $i,j$, let $r = "clip"(j - i, -k, k)$, where $k$ is a distance limit.

$ q_i = W_Q x_i, quad k_j = W_K x_j, quad v_j = W_V x_j $

$ e_(i j) = (q_i^T (k_j + a_r^K)) / sqrt(d) $
$ alpha_(i j) = exp(e_(i j)) / (sum_(j) exp(e_(i j))) $
$ y_i = sum_j alpha_(i j) (v_j + a_r^V) $

*Remark:* This explicitly models relative token distance by modifying the attention mechanism itself.


= Transformer-XL

Transformer-XL introduces *Segment-Level Recurrence*, allowing each segment to attend to cached hidden states from previous segments, but also causing a temporal confusion problem: tokens at identical indices across different segments shared the same positional encodings, making them indistinguishable.

For absolute positional encoding, let $x_i$ be the token embedding and $p_i$ the positional embedding. The attention score expands into four terms:

$
  e_(i j) & = (x_i + p_i)^T W_Q^T W_K (x_j + p_j) \
          & = x_i^T W_Q^T W_K x_j
            + x_i^T W_Q^T W_K p_j
            + p_i^T W_Q^T W_K x_j
            + p_i^T W_Q^T W_K p_j
$

These correspond to content-content, content-position, position-content, and position-position interactions.


Transformer-XL reparameterizes the four attention-score terms using relative positional encodings:

$
  e_(i j) & = x_i^T W_Q^T W_E x_j
            + x_i^T W_Q^T W_R r_(i-j)
            + u^T W_E x_j
            + v^T W_R r_(i-j)
$

$r_(i-j)$ is a fixed sinusoidal encoding of the relative distance.

$u,v$ are learned bias vectors shared across query positions within each attention head.


*Remark:* Relative positions avoid ambiguity caused by reusing absolute position indices across segments. Cached states extend the effective context, but gradients are stopped through the memory, and attention remains quadratic in the attended sequence length.


= T5

Add a learned relative-position bias directly to the query-key score:

$ e_(i j) = (q_i^T k_j) / sqrt(d) + b_(i - j) $

Offsets are commonly mapped to distance buckets, with different handling of nearby and distant positions.

*Remark:* No position-dependent value vectors are needed. Bucketing is inexpensive but sacrifices fine-grained information about very distant offsets.

= Rotary Position Embedding (RoPE)

Split query/key channels into two-dimensional pairs and rotate each pair with a position-dependent angle. Different pairs use different frequencies. For a rotation matrix $R(theta)$,

$ (R(i theta) q_i)^T (R(j theta) k_j) = q_i^T R((j - i) theta) k_j $


*Remark:* Although RoPE encodes absolute positions through rotations of queries and keys, their dot product depends on positional indices only through the relative displacement \(j-i\). This allows relative positional information to emerge naturally.

= Position Interpolation (PI)

For original context length $L$ and a longer target length $L^prime$, feed RoPE compressed positions to extend its context:

$ i^prime = i L / L^prime $

*Remark:* The modified positions remain in the familiar training range. Uniform interpolation can lose high-frequency positional resolution and generally benefits from adaptation or fine-tuning.



= YaRN

YaRN extends RoPE from context length $L$ to $L' = s L$ through frequency-dependent interpolation (*NTK-by-parts*), avoiding the loss of high-frequency information caused by uniform Position Interpolation.

For each rotary subspace $j$, define

$
  theta_j = b^(-(2j)/d),
  quad lambda_j = (2 pi) / theta_j,
  quad r(j) = L / lambda_j
$

where $r(j)$ measures the number of rotations within the original context length.

- *High-frequency components* ($r(j) >> 1$) have already completed many rotations during training. Their rotational phases have covered the full $2 pi$ cycle, so preserving their frequencies avoids disrupting learned local positional patterns.
- *Low-frequency components* ($r(j) < 1$) have covered only part of a rotation during training. Extending the context without modifying their frequencies introduces rotational phases outside the training range, potentially harming generalization.

Using two thresholds $alpha < beta$, define

$
  gamma_j = cases(
    0 quad & r(j) <= alpha,
    (r(j) - alpha) / (beta - alpha) quad & alpha < r(j) < beta,
    1 quad & r(j) >= beta,
  )
$

The modified rotary frequency is

$
  theta'_j = (1 - gamma_j) theta_j / s + gamma_j theta_j
$

For low-frequency components with $gamma_j = 0$, decreasing the frequency to $theta_j^' = theta_j / s$ preserves the original angular range.


For high-frequency components with $gamma_j = 1$, the original frequency is preserved.

Intermediate frequencies are smoothly blended.

YaRN additionally applies attention temperature scaling:

$
  "Attention" = "softmax" (
    (Q K^T) / (t sqrt(d))
  ),
  quad 1 / sqrt(t) = 1 + 0.1 ln(s)
$

The temperature rule is empirical. A larger $s$ leads to a smaller $t$, resulting in a more concentrated attention distribution.

*Remark:* YaRN interpolates low-frequency components to avoid unseen rotational phases while preserving high-frequency components to maintain local positional distinctions.  The interpolation thresholds and attention scaling require empirical tuning.

= Contextual Position Encoding (CoPE)

Estimate positions from *context-dependent gates* instead of counting every token equally. For a query at position $i$, learned gates determine which earlier tokens contribute to the contextual distance $p_(i j)$. Interpolate learned position embeddings for non-integer distances, then modify the score schematically as

$ e_(i j) = q_i^T k_j + z_i (p_(i j)) $

Here $z_i$ is the query-dependent interpolated position contribution.

*Remark:* Context-dependent counting can describe relationships such as sentence or entity distance. It is a positional-encoding alternative. Evidence is more limited for large models and diverse downstream tasks.

