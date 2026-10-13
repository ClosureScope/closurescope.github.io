#import "../typst/template.typ": *
#show: article.with(
  title: "Efficient Large Language Models",
  date: "2026-10-10",
  category: "LLM",
)

= Motivation

Efficient LLM design targets *latency*, *throughput*, *memory footprint*, and *quality*. For a model with $P$ parameters stored using $b$ bits per weight,

$ M_"weights" approx (P b) / 8 " bytes", quad "FLOPs"_"decode" approx 2 n P $

where $n$ is the number of generated tokens. These are rough estimates that exclude attention and other runtime overheads. Long contexts also increase attention computation and KV-cache traffic.

There are two complementary directions:

- *Efficient module design:* change the architecture of normalization, positions, attention, or FFNs.
- *Model compression:* quantize, prune, distill, approximate, or share parameters.

A reduction in parameters or theoretical FLOPs does not automatically imply lower latency: actual performance depends on memory traffic, kernels, hardware, and batching.

= Efficient Transformer Modules

== Normalization

=== LayerNorm, Post-LN, and Pre-LN

LayerNorm centers and rescales the features of each token:

$ "LN"(x) = gamma (x - mu) / sqrt(sigma^2 + epsilon) + beta $

The placement of normalization changes the residual path:

$ "Post-LN": quad x^' = "LN"(x + F(x)) $
$ "Pre-LN": quad x^' = x + F("LN"(x)) $

*Remark:* Post-LN can create unstable gradient scales in deep networks. Pre-LN preserves an explicit identity path and typically simplifies optimization. Neither removes the cost of normalization.

=== Mix-LN

Use Post-LN in earlier layers and Pre-LN in later layers, with a depth-dependent transition.

*Remark:* Tries to combine stronger early gradient signals with stable deep-layer optimization.

=== AdaNorm

Instead of learned affine gain and bias, AdaNorm applies an input-dependent multiplier to normalized features $y$. The scaling factor $phi(y)$ is detached during backpropagation.
$ y = (x - mu) / sqrt(sigma^2 + epsilon) $
$ phi(y) = C (1 - k y), quad z = phi(y) y $



*Remark:* Simplifies the affine portion of normalization and can improve convergence in evaluated settings. The positivity and scaling behavior of $phi$ must be controlled.

=== ReZero

Remove normalization and learn a scalar gate for each residual branch:

$ x^' = x + alpha F(x), quad alpha = 0 " at initialization" $

*Remark:* Initially, the network is an identity mapping, facilitating stable deep optimization. Stability then depends on the learned residual scaling; this is a different approach from simplifying LayerNorm.

=== nGPT

Normalize all vectors including embeddings, attending outputs, and MLP outputs to unit norm throughout the network:

$ hat(x) = x / norm(x)_2 $

*Remark:* Maintains stable output scaling and enable fast training without conventional LayerNorm or weight decay.

=== GPT-2

Remove LayerNorm from a pretrained model and recover quality with further fine-tuning.

*Remark:* GPT-2 indicates that some trained models tolerate normalization removal surprisingly well. This does not establish that normalization is unnecessary during initial training.

=== RMSNorm

Normalize by the root mean square, without subtracting the mean:

$ "RMSNorm"(x) = gamma x / sqrt(sigma^2 + epsilon) $

*Remark:* Cheaper than mean-centered LayerNorm and widely used in modern LLMs. It provides scale normalization rather than mean invariance.

=== Dynamic Tanh (DyT)

Based on the observation that the behavior of LayerNorm closely resembles that of $tanh$, replace explicit mean/variance calculations with a learned scaled nonlinearity.

$ "DyT"(x) = gamma tanh(alpha x) + beta $

*Remark:* Offers a simple normalization alternative with competitive results on evaluated models.

== Positional Encoding

=== Sinusoidal Absolute Position Embedding

The original Transformer adds sinusoidal features to the token embedding:

$ "PE"_(p, 2 i) = sin(p / 10000^((2 i) / d)) $
$ "PE"_(p, 2 i + 1) = cos(p / 10000^((2 i) / d)) $

*Remark:* Simple and parallelizable, but fails to model relative distances and long-context behavior beyond the trained range is not guaranteed.


=== Shaw-style Relative Position Encoding

Add learned, clipped relative-position vectors to both keys and values.

For token positions $i,j$, let $r = "clip"(j - i, -k, k)$, where $k$ is a distance limit.

$ q_i = W_Q x_i, quad k_j = W_K x_j, quad v_j = W_V x_j $

$ e_(i j) = (q_i^T (k_j + a_r^K)) / sqrt(d) $
$ alpha_(i j) = exp(e_(i j)) / (sum_(j) exp(e_(i j))) $
$ y_i = sum_j alpha_(i j) (v_j + a_r^V) $

*Remark:* This explicitly models relative token distance by modifying the attention mechanism itself.


=== Transformer-XL

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


=== T5

Add a learned relative-position bias directly to the query-key score:

$ e_(i j) = (q_i^T k_j) / sqrt(d) + b_(i - j) $

Offsets are commonly mapped to distance buckets, with different handling of nearby and distant positions.

*Remark:* No position-dependent value vectors are needed. Bucketing is inexpensive but sacrifices fine-grained information about very distant offsets.

=== Rotary Position Embedding (RoPE)

Split query/key channels into two-dimensional pairs and rotate each pair with a position-dependent angle. Different pairs use different frequencies. For a rotation matrix $R(theta)$,

$ (R(i theta) q_i)^T (R(j theta) k_j) = q_i^T R((j - i) theta) k_j $


*Remark:* Although RoPE encodes absolute positions through rotations of queries and keys, their dot product depends on positional indices only through the relative displacement \(j-i\). This allows relative positional information to emerge naturally.

=== Position Interpolation (PI)

For original context length $L$ and a longer target length $L^prime$, feed RoPE compressed positions to extend its context:

$ i^prime = i L / L^prime $

*Remark:* The modified positions remain in the familiar training range. Uniform interpolation can lose high-frequency positional resolution and generally benefits from adaptation or fine-tuning.



=== YaRN

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

=== Contextual Position Encoding (CoPE)

Estimate positions from *context-dependent gates* instead of counting every token equally. For a query at position $i$, learned gates determine which earlier tokens contribute to the contextual distance $p_(i j)$. Interpolate learned position embeddings for non-integer distances, then modify the score schematically as

$ e_(i j) = q_i^T k_j + z_i (p_(i j)) $

Here $z_i$ is the query-dependent interpolated position contribution.

*Remark:* Context-dependent counting can describe relationships such as sentence or entity distance. It is a positional-encoding alternative. Evidence is more limited for large models and diverse downstream tasks.

== Attention

For reference, standard scaled dot-product attention is

$ "Attention"(Q, K, V) = "softmax"((Q K^T) / sqrt(d)) V $
=== Multi-Query Attention
==== Multi-Query Attention (MQA)

Each attention head uses its own query projection $W_Q$, while all heads share the same key and value projections $W_K$ and $W_V$, thus sharing the same $K$ and $V$.

*Remark:* Dramatically reduces autoregressive KV-cache size and memory traffic. Sharing all KV representations can reduce head diversity.

==== Grouped-Query Attention (GQA)

Divide the heads into groups. Within each group, each attention head shares the same $K$ and $V$.

*Remark:* Provides a continuous trade-off between MHA and MQA, often retaining accuracy with much lower cache bandwidth. Full attention over a sequence is still quadratic.

==== Multi-Token Attention (MTA)

Process attention-score matrix with a lightweight $3 times 3$ 2D convolution to capture information between adjacent tokens, followed by cross-head 1D convolution to integrate information across heads.

*Remark:* Captures adjacent-token and cross-head patterns with few extra parameters. Convolution adds operators and does not inherently remove quadratic attention complexity.
=== Low-Complexity Attention

==== Kernel-Based Attention

Standard transformer attention is defined as

$ Y = "softmax"((Q K^T) / sqrt(d)) V $

Or in scalar form,

$ e_(i j) = (q_i^T k_j) / sqrt(d) $
$ alpha_(i j) = exp(e_(i j)) / (sum_(j) exp(e_(i j))) $
$ y_i = sum_j alpha_(i j) v_j $


The exponentiated logits can be interpreted as evaluations of an exponential dot-product kernel:

$
  kappa(q_i, k_j)
  = exp((q_i^T k_j) / sqrt(d))
$
$ alpha_(i j) = kappa(q_i, k_j) / (sum_(j) kappa(q_i, k_j)) $

Let $kappa(Q, K)$ denote the matrix of pairwise kernel values, with entries $kappa(q_i, k_j)$.

Define the normalization denominator

$
  D = "diag"( kappa(Q, K) bold(1))
$

Then normalized kernel attention can be written as

$
  Y = D^(-1) kappa(Q, K) V
$

We now focus on $kappa(Q, K) V$ to analyze the complexity.
Note that
$Q, K, V in RR^(n times d)$.

$kappa(Q, K)$ is $RR^(n times d) times RR^(d times n)$, $kappa V$ is $RR^(n times n) times RR^(n times d)$, resulting in a $O(n^2)$ complexity.

The key observation is that, if we can use the associativity to calculate $K^T V$ first, $K^T V$ is $RR^(d times n) times RR^(n times d)$, $Q (K^T V)$ is $RR^(n times d) times RR^(d times d)$, resulting is a $O(n)$ complexity.

However, the $"exp"$ operation in the original $kappa$ stops us from using associativity. In order to exploit the associativity, we need that $kappa$ can be factorized into two respective  matrices of $Q$ and $V$.
To achieve this, kernel-based attention seeks a finite-dimensional feature-map representation of the kernel:

$
  kappa(q_i, k_j) = phi(q_i)^T phi(k_j)
$
$
  kappa(Q, K) = phi(Q) phi(K)^T
$

where $phi: RR^(d) -> RR^r$ is a feature map. Positive-semidefinite kernels admit inner-product representations in feature spaces, which may be infinite-dimensional. Efficient linear attention requires a finite-dimensional representation or approximation.

With this factorization, the unnormalized attention computation becomes

$
  kappa(Q, K) V
  = (phi(Q) phi(K)^T) V
  = phi(Q) (phi(K)^T V)
$

Similarly, we can compute $D$ as
$
  D = "diag"( kappa(Q, K) bold(1)) = "diag"(phi(Q) (phi(K)^T bold(1)))
$

Thus
$
  Y = D^(-1) phi(Q) (phi(K)^T V)
$

The complexity of full-sequence attention without a causal mask is thus reduced to $O(n)$.

For autoregressive inference with a causal mask, each position $t$ can only attend to positions $j <= t$,
$ Y = D^(-1) (M dot.o kappa(Q, K)) V = D^(-1) (M dot.o (phi(Q) phi(K)^T)) V $
$ D = "diag"((M dot.o kappa(Q, K)) bold(1)) = "diag"((M dot.o (phi(Q) phi(K)^T)) bold(1) ) $
Due to the Hadamard product, we can not apply the associativity. However, for each position $t$,
$
  y_t = D^(-1) phi(q_t)^T (phi(K_t)^T V) =
  (phi(q_t)^T sum_(j=1)^t phi(k_j) v_j^T) /
  (phi(q_t)^T sum_(j=1)^t phi(k_j))
$

Directly recomputing these prefix sums at every position would result in $1 + 2 + dots + n = O(n^2)$ complexity. Obviously, we can maintain two recurrent states:

$
  S_t = sum_(j=1)^t phi(k_j) v_j^T,
  quad z_t = sum_(j=1)^t phi(k_j)
$

These can be updated incrementally:

$
  S_t = S_(t-1) + phi(k_t) v_t^T,
  quad z_t = z_(t-1) + phi(k_t)
$

with $S_0 = 0$ and $z_0 = 0$. The attention output is then

$
  y_t = (phi(q_t)^T S_t) / (phi(q_t)^T z_t)
$

Since $phi(q_t) in RR^r$, $S_t in RR^(r times d)$, $z_t in RR^r$, each step requires $O(1)$ time.


Therefore, autoregressive inference over $n$ steps requires $O(n)$ total time and only $O(1)$ memory for the recurrent states. In this architecture, transformers are RNNs.

Different architectures follow two main approaches:

- *Linear Transformer* defines a new kernel through a feature map, allowing exact factorization of the new kernel.
- *Performer* uses randomized feature maps to approximate the original exponential dot-product kernel, aiming to preserve softmax attention while reducing computational complexity.


===== Linear Transformer


Linear Transformer adopts a simple feature map:

$
  phi(x) = "ELU"(x) + 1
$

where ELU is applied elementwise. Since $phi(x)$ is positive, the resulting kernel $kappa$ is positive, allowing positive similarities and valid attention normalization.

This defines a new kernel rather than approximating the original exponential dot-product kernel.

*Remark:* Linear Transformer achieves $O(n)$ complexity with or without a causal mask.


===== Performer (FAVOR+)

Unlike Linear Transformer, which defines a new kernel, Performer aims to approximate the original exponential dot-product kernel:

$
  kappa(q_i, k_j)
  = exp((q_i^T k_j) / sqrt(d))
$

Performer introduces FAVOR+ (*Fast Attention Via Positive Orthogonal Random Features*), which constructs a randomized feature map $phi: RR^(d) -> RR^r$.

$
  phi(x)_a = 1 / sqrt(r) exp(
    (omega_a^T x) / d^(1/4)
    - norm(x)^2 / (2 sqrt(d))
  ),
  quad a = 1, dots, r
$

where each $omega_a in RR^(d)$ has a standard Gaussian marginal distribution. FAVOR+ uses orthogonalized random projections, with appropriate scaling, to reduce estimation variance.

This feature map satisfies

$
  E_omega [phi(q_i)^T phi(k_j)]
  = kappa(q_i, k_j)
$

Thus, the softmax kernel can be approximated by

$
  kappa(q_i, k_j)
  approx phi(q_i)^T phi(k_j)
$

$phi(x)$ is positive, ensuring positive estimated kernel values and valid attention normalization.

*Remark:* Performer achieves $O(n)$ complexity with or without a causal mask. Unlike Linear Transformer, Performer aims to preserve the original softmax kernel rather than replacing it with a different similarity function. Orthogonal random projections reduce approximation variance. However, finite-dimensional random features introduce estimation error.

===== Flash Linear Attention (FLA)

Linear attention has an attractive recurrent formulation, but a linear-time algorithm is not necessarily a fast GPU algorithm. FLA aims to improve the parallelism of linear attention with a causal mask.

To see the motivation, recall

$
  S_t = S_(t-1) + phi(k_t) v_t^T,
  quad z_t = z_(t-1) + phi(k_t)
$

Sequential dependencies of recurrent states limit parallelism when all training tokens are available.


We first split the sequence in chunks. Let the chunk size be $B$, and define $b_c = c B$ as the last token position of chunk $c$. Write $Q^(c), K^(c), V^(c)$ for the query, key, and value matrices of chunk $c$.

The state at the end of chunk $c$ satisfies

$
  S_(b_c) = S_(b_(c-1)) + phi(K^(c))^T V^(c)
$
We now update the boundary state once per chunk.

The boundary states can be computed in a recurrent way. Given these states, the outputs of different chunks can be computed in parallel.


For a token $t$ within chunk $c$, its state can be decomposed into two parts:

$
  S_t
  = S_(b_(c-1))
  + sum_(j=b_(c-1)+1)^t phi(k_j) v_j^T
$
$
  z_t
  = z_(b_(c-1))
  + sum_(j=b_(c-1)+1)^t phi(k_j)
$

Therefore,

$ phi(q_t)^T S_t = phi(q_t)^T S_(b_(c-1)) + phi(q_t)^T sum_(j=b_(c-1)+1)^t phi(k_j) v_j^T $
$ phi(q_t)^T z_t = phi(q_t)^T z_(b_(c-1)) + phi(q_t)^T sum_(j=b_(c-1)+1)^t phi(k_j) $
For the whole chunk,
$
  N^c = mat(phi(q_t)^T S_t; phi(q_(t+1))^T S_(t+1); phi(q_(t+2))^T S_(t+2)) = phi(Q^c) S_(b_(c-1)) + (M dot.o (phi(Q^c) phi(K^c)^T)) V^c
$
$
  D^c = "diag"mat(phi(q_t)^T z_t; phi(q_(t+1))^T z_(t+1); phi(q_(t+2))^T z_(t+2)) = "diag"(phi(Q^c) z_(b_(c-1)) + (M dot.o (phi(Q^c) phi(K^c)^T)) bold(1))
$
$ Y^c = (D^c)^(-1) N^c $

The first term represents *inter-chunk memory*, while the second represents *intra-chunk causal attention*.

*Remark:* FLA addresses the sequential dependence of linear attention and improve its parallelism through chunking.

