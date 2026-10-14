#import "../../typst/template.typ": *
#show: article.with(
  title: "Efficient LLMs",
)


==== Low-Rank Attention

Instead of approximating the pairwise *similarity function*, low-rank attention reduces the number of keys and values against which queries interact. This changes the *sequence dimension*, not necessarily the hidden dimension.

===== Linformer

For $Q,K in RR^(n times d)$ and $V in RR^(n times d_v)$, ordinary attention forms an $n times n$ score matrix. Linformer (Wang et al., 2020) starts from the hypothesis that the effective attention map can be represented with a much smaller rank $r$.

Linformer learns projections along the sequence axis:

$
  E,F in RR^(r times n), quad r << n
$

and define

$
  K^prime = E K, quad V^prime = F V
$

Then $K^prime in RR^(r times d)$ and $V^prime in RR^(r times d_v)$.

The resulting operation is

$
  Y = "softmax" ((Q (K^prime)^T) / sqrt(d)) V^prime
$

The score matrix now has shape $n times r$ instead of $n times n$. With efficient projections, the dominant cost is $O(n r d)$ rather than $O(n^2 d)$ when $r$ is much smaller than $n$.

The learned $E$ and $F$ may be shared across heads or layers. They compress information rather than simply select $r$ tokens.

*Remark:* Linformer exploits low effective rank in *token interactions*. Sequence-length reduction loses information, and the original fixed-length projection scheme does not immediately provide unrestricted causal streaming.

===== FLuRKA

Linformer compresses tokens, while Performer-like methods factorize a similarity kernel. FLuRKA (Gupta et al.) asks whether these two savings can be combined in the *same attention computation*.

As in Linformer, let

$
  K^prime = E K, quad V^prime = F V
$

where $E,F in RR^(r times n)$ and $r << n$.

If

$
  kappa(q, k) approx phi(q)^T phi(k)
$

then a *normalized kernel-attention schematic* is

$
  Y = D^(-1) phi(Q) (phi(K^prime)^T V^prime)
$

with

$
  D = "diag" (phi(Q) (phi(K^prime)^T bold(1)))
$

This combines two approximations and need not equal full softmax attention.

With $phi(Q) in RR^(n times m)$ and $phi(K^prime) in RR^(r times m)$, compute the $m times d_v$ intermediate representation first

$
  U = phi(K^prime)^T V^prime
$

Then form $phi(Q) U$. This avoids both a full $n times n$ attention matrix and a full $n times r$ kernel-value product.

*Remark:* FLuRKA combines *sequence compression* and *kernel factorization*, so it incurs both low-rank and feature-map approximation errors. It is a fused approximation, not simply two independent attention layers stacked sequentially.

===== Luna

Luna (Ma et al., 2021) uses a different idea: instead of a fixed matrix projection $E$, introduce a short auxiliary sequence that *learns how to summarize* the full input.

Let $X in RR^(n times d)$ be the input and $P in RR^(r times d)$ be an auxiliary sequence, where $r << n$.

For the non-causal case, write

$
  A_"pack" = "softmax" ((P X^T) / sqrt(d))
$

and

$
  Z = A_"pack" X
$

The result $Z in RR^(r times d)$ summarizes $n$ tokens using only $r$ packed vectors.

Use the original token representations as queries and the packed representations as keys and values:

$
  A_"unpack" = "softmax" ((X Z^T) / sqrt(d))
$

$
  Y = A_"unpack" Z
$

Both score matrices have $O(n r)$ entries. This is the non-causal intuition; full Luna also updates its auxiliary sequence.

Causal modeling needs a different packing rule. In causal Luna, ordinary pack softmax over the entire input would leak future-token information through its denominator. The original paper therefore uses causal accumulation and non-softmax positive activations for packing, while unpacking across the fixed auxiliary dimension may use softmax.

*Remark:* Luna learns a compact *sequence-level information bottleneck* using two nested attention operations. Its non-causal formula is simple, but the causal version must be constructed carefully to prevent future-token leakage.

== Feed-Forward Networks and Experts

=== Dense FFN

Attention exchanges information *between tokens*, while the FFN transforms the representation *within each token*. A standard two-projection FFN is

$
  h = sigma(W_1 x + b_1), quad y = W_2 h + b_2
$

where $W_1 in RR^(d_f times d)$ and $W_2 in RR^(d times d_f)$. With $d_f$ several times larger than $d$, the weight count is approximately $2 d d_f$ per layer, making the FFN a natural target for architectural optimization.

*Remark:* Dense FFNs parallelize well, but every token executes the same large parameter matrices.

=== GLU, ReGLU, GEGLU, and SwiGLU

A conventional FFN applies one nonlinearity to a single expanded representation. Shazeer (2020) introduces an extra path that *gates* the features of the other path.

Define a value path and an activated gate path:

$
  u = W_v x, quad g = W_g x
$

With a gating activation $f$,

$
  "GatedFFN" (x) = W_o (u dot.o f(g))
$

The choices $f = "sigmoid"$, $f = "ReLU"$, $f = "GELU"$, and $f = "SiLU"$ give GLU, ReGLU, GEGLU, and SwiGLU, respectively. For example,

$
  "SiLU" (z) = z "sigmoid" (z)
$

A standard FFN has two main matrices whereas a gated FFN has three. If the conventional intermediate width is $d_f$, an equal-parameter comparison commonly uses a smaller gated intermediate width, approximately $2 d_f / 3$ when all three matrices connect to the same model width.

*Remark:* Multiplicative gating improves expressive control over features, but three projections do not automatically mean fewer FLOPs. SwiGLU is widely used because its empirical quality-to-compute trade-off is strong.

=== MobileBERT

MobileBERT (Sun et al., 2020) explores a complementary constraint: mobile deployment limits the width of internal representations, but a narrow single FFN may have insufficient capacity.

MobileBERT keeps a narrow bottleneck representation and compensates by stacking several FFNs within one Transformer block:

$
  h_0 = x, quad h_(j+1) = "FFN"_j (h_j), quad j = 0, dots, m-1
$

MobileBERT additionally uses bottleneck transformations and carefully designed teacher-student training; the stack is one part of the full architecture.

*Remark:* MobileBERT trades additional *depth* for a narrower model and targets encoder-based mobile inference. It should not be treated as a drop-in FFN replacement for every decoder-only LLM.

=== Mixture of Experts (MoE)

A dense FFN applies every parameter to every token. If we want *many parameters* but only *a small fraction of computation* per token, we can partition the FFN capacity into experts and route each token to a subset.

With $E$ experts,

$
  p(x) = "softmax" (W_r x), quad p(x) in RR^E
$

Let $cal(T) (x) = "TopK" (p(x), k)$ contain $k$ expert indices. The expert result is

$
  y = sum_(e in cal(T) (x)) g_e (x) "FFN"_e (x)
$

where the nonnegative $g_e (x)$ are router weights, sometimes renormalized over the selected experts.

If each expert has $P_e$ parameters, expert storage is roughly $E P_e$, but only $k P_e$ expert parameters are activated per token. All experts still require storage, and distributed routing entails communication.

*Remark:* MoE is primarily a *conditional computation* architecture. Its main advantage is increasing total capacity without linearly increasing active per-token FLOPs, not necessarily shrinking the model's total memory footprint.

=== GShard

GShard (Lepikhin et al., 2020) scales MoE to distributed training and introduces practical routing controls.

GShard sends each token to at most two routed experts, with capacity limits to avoid overload.

With $N$ tokens, $E$ experts, and capacity factor $c$, an illustrative capacity is

$
  C = "ceil" (c N / E)
$

per expert per group. Depending on the concrete top-2 dispatch algorithm, overflow tokens may be rerouted, dropped from expert computation, or carried by a residual path.

Sparse token dispatch lets each device execute only its assigned expert matrices, while load-balancing mechanisms discourage overloaded experts.

*Remark:* GShard shows how sparse FFNs scale across devices. Top-2 routing, capacity constraints, and communication are as important as the expert formula itself.

=== Switch Transformer

Switch Transformer (Fedus et al., 2022) asks whether MoE routing can be simplified further.

Let

$
  e^*(x) = "argmax"_e p_e (x)
$

and compute

$
  y = p_(e^*(x)) (x) "FFN"_(e^*(x)) (x)
$

up to the surrounding residual pathway and expert-capacity handling.

A router can send most tokens to a few popular experts. An auxiliary loss encourages both the fraction of dispatched tokens and the router's average probability mass to be spread across experts. In schematic form,

$
  cal(L)_"balance" prop E sum_(e=1)^E f_e P_e
$

where $f_e$ is the observed fraction of tokens assigned to expert $e$ and $P_e$ is its mean routing probability.

*Remark:* Top-1 routing reduces dispatch complexity relative to Top-2. It makes capacity management and router balance more important, not less.

=== BASE Layers

Most sparse expert models address imbalance through auxiliary penalties. BASE Layers (Lewis et al., 2021) replaces heuristic balancing with a *constrained assignment problem*.

Let $s_(i e)$ be the learned compatibility between token $i$ and expert $e$.

With binary assignment variables $a_(i e)$ and $N$ divisible by $E$, solve

$
  max_a sum_(i=1)^N sum_(e=1)^E a_(i e) s_(i e)
$

subject to

$
  sum_e a_(i e) = 1, quad sum_i a_(i e) = N / E
$

The hard capacity balance follows from the optimization constraints rather than from a soft load-balancing penalty.

*Remark:* BASE eliminates balancing-loss tuning by treating routing as a combinatorial allocation problem, but balanced assignment itself incurs overhead and constrains batching.

=== GLaM

GLaM (Du et al., 2022) uses sparsely activated, distributed expert layers to grow capacity while controlling training and inference computation.

A large pool of FFN experts holds most model parameters.

With $cal(T) (x)$ the two selected experts,

$
  y = sum_(e in cal(T) (x)) g_e (x) "FFN"_e (x)
$

The resulting compute depends mainly on two active experts per token, even though the total parameter count can be much larger.

*Remark:* GLaM illustrates *scaling total capacity at bounded active compute*. Its system-level efficiency depends heavily on parallelism, batching, and inter-device communication.

=== MoEfication

Standard MoE designs train separate experts. MoEfication (Zhang et al., 2022) asks whether the neurons *inside an existing dense FFN* already behave like latent experts.

Partition the FFN's intermediate channels into sets $cal(E)_1, dots, cal(E)_M$ using co-activation statistics.

If

$
  h = sigma(W_1 x), quad y = W_2 h
$

and $h_e$ denotes the coordinates in group $cal(E)_e$, then

$
  y = sum_(e=1)^M (W_2)_e h_e
$

where $(W_2)_e$ is the corresponding output-projection column block.

A router estimates the groups most relevant to the token and approximates

$
  y approx sum_(e in cal(T) (x)) (W_2)_e h_e
$

*Remark:* MoEfication converts a pretrained dense FFN into conditional block computation without training an MoE from scratch. Sparse block execution must be efficient for the theoretical savings to become real speedups.

=== Mixtral

Mixtral 8x7B (Jiang et al., 2024) makes the sparse expert design concrete at practical LLM scale.

Self-attention remains a separate shared component.

Define $cal(T) (x) = "TopK" (p(x), 2)$ and

$
  y = sum_(e in cal(T) (x)) g_e (x) "FFN"_e (x)
$

The router weights depend on the token, allowing different tokens in the same sequence to activate different expert pairs.

*Remark:* Mixtral offers large *total* expert capacity with two experts active per token. Its model storage still includes all eight experts; it is not equivalent to a dense 7B model in memory use.

=== DeepSeekMoE

Top-$k$ experts can become redundant because each large expert may learn both general and specialized knowledge. DeepSeekMoE (Dai et al., 2024) introduces *fine-grained expert segmentation* and *shared expert isolation*.

Instead of selecting $k$ of $E$ large experts, split each into $m$ smaller experts and select roughly $m k$ of the resulting $m E$ experts. This makes the active expert combination more flexible at a comparable parameter budget.

Let $cal(S)$ be the shared experts and $cal(T) (x)$ the token-specific routed experts. The MoE output has the structure

$
  y = sum_(e in cal(S)) "FFN"_e (x)
  + sum_(e in cal(T) (x)) g_e (x) "FFN"_e (x)
$

Shared experts can absorb broadly useful representations while the routed pool specializes in token-dependent patterns. Actual DeepSeekMoE implementations include additional routing and balancing choices.

*Remark:* Smaller routed experts offer finer specialization, while always-on shared experts reduce duplicated general knowledge. The extra routing flexibility may raise communication costs.

= Model Compression

Architecture redesign changes which operations a model performs. *Model compression* instead tries to reduce the cost of a model already trained, although some methods also change its parameterization and require further training. We distinguish quantization, pruning, distillation, approximation, and sharing because they remove different kinds of redundancy.

== Quantization

A floating-point tensor contains much more precision than many inference calculations need. Given real values $x$, a scale $s > 0$, integer zero-point $z$, and integer bounds $q_"min", q_"max"$, uniform affine quantization is

$
  q = "clip" ("round" (x / s) + z, q_"min", q_"max")
$

The reconstructed value is

$
  hat(x) = s (q-z)
$

Quantization error is $epsilon_q = hat(x)-x$. Lower bit widths reduce the size of stored tensors, but their effect on speed depends on whether the hardware can efficiently execute the resulting operations.

=== Post-Training Quantization (PTQ)

PTQ starts with pretrained weights and performs quantization without full model retraining. An important distinction is between *weight-only* PTQ, which primarily reduces persistent model storage, and *weight-activation* PTQ, which may also replace expensive matrix multiplication with lower-precision arithmetic.

==== Rounding-to-Nearest (RTN)

The simplest baseline chooses the nearest quantization-grid point:

$
  hat(w) = s "round" (w/s)
$

with clipping and possibly a zero-point for a finite quantization range. Grid parameters may be chosen per tensor, channel, or group.

The underlying assumption is that small *weight-space* rounding error leads to small *model-output* error. This ignores whether different weights have different effects on the computation.

*Remark:* RTN is fast and training-free, but it is a weak baseline at very low precision because it does not use output sensitivity.

==== GPTQ

GPTQ (Frantar et al., 2022) improves on RTN by asking which quantization errors a linear layer can compensate for using its remaining weights.

For a layer with $Y = W X$, where $X in RR^(d_"in" times N)$ stores calibration inputs,

$
  cal(L)_"recon" (hat(W))
  = norm((W-hat(W)) X)_F^2
$

This error is more relevant than $norm(W-hat(W))_F^2$ because it weights directions according to observed activations.

For each output row, the quadratic objective has an input-side Hessian proportional to

$
  H = 2 X X^T
$

usually stabilized with damping. If a weight is forced from $w_j$ to $hat(w_j)$, the optimal correction to the still-unquantized coordinates depends on $H^(-1)$.

With a suitable Hessian inverse approximation, the classical second-order quantization update has the form

$
  delta(w) = -(w_j-hat(w_j)) / (H^(-1))_(j j) dot H^(-1)_(:,j)
$

for the relevant active coordinates. GPTQ makes this idea practical by processing columns in a shared order, batching updates, and using efficient matrix factorizations.

*Remark:* GPTQ is calibration-aware *second-order reconstruction*, not simply more careful rounding of large weights. It mainly targets weight-only PTQ; low bit width does not by itself ensure faster kernels.

==== Activation-Aware Weight Quantization (AWQ)

GPTQ corrects reconstruction errors after choosing quantized weights. AWQ (Lin et al., 2024) instead identifies weights whose *input activation channels* make them especially important.

In a linear map $Y = X W$, large values in input channel $j$ can amplify error from quantizing the corresponding row of $W$.

For an invertible positive diagonal matrix $S$,

$
  X W = (X S^(-1)) (S W)
$

This equality holds in full precision. Scaling selected weight rows upward can improve their effective resolution under subsequent quantization, while activation scaling compensates for the transformation.

Choose the scales to minimize a quantity of the form

$
  min_S norm(X W - X S^(-1) Q(S W))_F^2
$

where $Q$ denotes the weight quantizer. AWQ searches a small scale family using calibration data

*Remark:* AWQ protects channels indicated by *activation statistics*, while GPTQ emphasizes *curvature-based reconstruction*. AWQ is not merely a magnitude-based weight-selection rule.

==== QuIP\#

At very low bit widths, a few large coordinates can consume most of a quantizer's dynamic range. QuIP\# (Tseng et al., 2024) uses the idea of *incoherence*: change the basis so that information is spread over many coordinates.

Let $R_1, R_2$ be orthogonal matrices. Then

$
  W = R_1^T (R_1 W R_2^T) R_2
$

Quantize the rotated matrix $W^prime = R_1 W R_2^T$ instead of $W$. QuIP\# constructs efficient randomized rotations from Hadamard transforms and sign flips.

Rather than map each scalar to an independent grid point, partition the rotated weights into vectors $w_g$ and use a codebook $cal(C)$:

$
  hat(w_g) = "argmin"_(c in cal(C)) norm(w_g-c)^2
$

QuIP\# combines this with second-order adaptive rounding and an $E_8$-lattice codebook

Inter-layer fine-tuning compensates for errors that remain after the rotation and lattice quantization.

*Remark:* QuIP\# combines randomized Hadamard *incoherence processing*, structured *vector quantization*, and recovery tuning. Its advantage in extreme low-bit settings comes with specialized coding and decoding requirements.

==== Additive Quantization for LLMs (AQLM)

A scalar quantizer chooses one grid value for each weight. AQLM (Egiazarian et al., 2024) represents a *vector* of weights using the sum of several codewords.

For a group $w_g in RR^p$, learn $M$ codebooks $C_1, dots, C_M$.

Store discrete indices $c_1, dots, c_M$ such that

$
  hat(w_g) = sum_(m=1)^M C_m[c_m]
$

This forms many possible reconstructions from relatively small codebooks without storing each full-precision vector.

Codebooks and assignments are optimized to preserve layer or block outputs, not just isolated individual weights.

*Remark:* AQLM trades a simple integer grid for a richer *compositional codebook*. Compression can be strong, but inference must decode or directly compute with the additive representation.

==== LeanQuant

Weight values with similar magnitudes can have very different importance to the model's reconstruction error. LeanQuant (Zhang and Shrivastava, 2024) makes the *quantization grid* itself sensitivity-aware.

A uniform grid primarily fits the weight distribution. A second-order PTQ procedure also depends on the diagonal entries of the *inverse Hessian*.

For a candidate rounding error $delta_j$, a local second-order cost in an error-compensated quantizer is related to

$
  cal(E)_j prop delta_j^2 / (H^(-1))_(j j)
$

up to the particular quantization algorithm and objective. This suggests that grid design should account for sensitivity, not only the weight range.

LeanQuant incorporates learned, loss-error-aware grids into an efficient iterative PTQ procedure, including affine and nonuniform choices.

*Remark:* LeanQuant changes *which representable values are available* to the quantizer. The inverse-Hessian diagonal is not itself a replacement for the reconstruction objective; it guides how errors should be priced.

=== Weight-Activation PTQ

Weight-only quantization reduces model storage but still often multiplies high-precision activations by dequantized weights. Weight-activation PTQ targets both operands of matrix multiplication, which makes activation outliers an especially important difficulty.

==== LLM.int8()

LLM.int8() (Dettmers et al., 2022) observes that a small set of hidden-state dimensions can contain large outlier values. Quantizing those features together with ordinary features may introduce disproportionate error.

Write

$
  X = [X_"normal", X_"outlier"]
$

and partition the corresponding rows of $W$ accordingly.

The linear map decomposes exactly as

$
  X W = X_"normal" W_"normal"
  + X_"outlier" W_"outlier"
$

Approximate the normal product with vector-wise INT8 quantization while evaluating the outlier part in higher precision.

The expensive high-precision path remains small because it handles only exceptional hidden-state dimensions.

*Remark:* LLM.int8() is an *outlier-aware mixed-precision decomposition*, not fully integer-only computation. Its efficiency depends on how cheaply the exceptional path can be executed.

==== SmoothQuant

LLM.int8() separates the outliers into a high-precision path. SmoothQuant (Xiao et al., 2023) aims to make the *entire* linear layer easier to quantize in W8A8 without such a split.

Use an exact channel-wise rescaling identity. For $Y = X W$ and diagonal $S = "diag" (s_1, dots, s_d)$,

$
  X W = (X S^(-1)) (S W)
$

An activation channel with large magnitude becomes smaller after division by $s_j$, while the corresponding weight row becomes larger.

Let $a_j$ be a calibration estimate of the maximum absolute activation in channel $j$ and $w_j$ the maximum absolute value of the corresponding weight row. SmoothQuant uses a scale of the form

$
  s_j = a_j^alpha / w_j^(1-alpha)
$

where $0 <= alpha <= 1$ controls how much quantization difficulty moves from activations to weights.

Wherever the architecture permits, the inverse activation scaling is absorbed into preceding parameters so the serving graph need not perform an additional explicit per-token transform.

*Remark:* SmoothQuant turns difficult activation outliers into a more balanced weight-activation distribution by an *equivalent pre-quantization transformation*. The equivalence is exact before rounding, not after it.

==== Outlier Suppression+ (OS+)

SmoothQuant rescales channels but does not directly correct the *asymmetry* of their value distributions. OS+ (Wei et al., 2023) introduces both channel-wise shifting and scaling.

For a channel-wise shift vector $c$, rewrite a linear layer with bias $b$ as

$
  X W + b = (X-bold(1) c^T) W + (b+c^T W)
$

where $bold(1)$ broadcasts the shift to all tokens.

Using a diagonal matrix $S$,

$
  X W + b
  = ((X-bold(1)c^T) S^(-1)) (S W)
  + b+c^T W
$

Calibration statistics and an optimization objective determine which transformations best suppress asymmetric, concentrated outliers.

*Remark:* OS+ generalizes scale-only smoothing with *shift plus scale*. The extra affine parameters can be folded when surrounding layers support the transformation.

==== QLLM

Even after channel scaling, a few outlier dimensions may dominate the quantization range. QLLM (Liu et al., 2023) modifies the *channel representation* instead of relying only on one scale per original channel.

An extreme input channel may be split into smaller contributions, while sufficiently similar channels can be merged, with corresponding changes to the weight representation.

A simple exact split illustrates the idea:

$
  x_j w_j^T = (x_j/a) (a w_j^T)
$

and a representation can distribute a contribution over multiple new channels, provided their summed product equals the original. QLLM's adaptive channel reassembly is more elaborate than this single-channel identity.

After channel changes and quantization, use a layerwise error-reconstruction procedure to reduce output mismatch.

*Remark:* QLLM attacks activation outliers by *changing channel granularity* and compensating their errors. The basic identities explain reassembly but do not specify the complete learned reassembly algorithm.

==== SpinQuant

An orthogonal change of basis preserves exact full-precision linear algebra but changes how values are distributed across coordinates. SpinQuant (Liu et al., 2024) learns such rotations for low-bit quantization.

For orthogonal $R$ with $R^T R = I$,

$
  X W = (X R) (R^T W)
$

Quantization is coordinate-dependent, so different valid orthogonal rotations can give very different rounding errors. SpinQuant optimizes rotation parameters using calibration data and orthogonality-preserving methods.

The learned rotations make weights, activations, and, in suitable architectural placements, KV-cache states more compatible with low-bit quantization.

*Remark:* Rotation is *lossless before quantization* but useful because rounding is not rotation-invariant. A learned rotation can outperform a random one, at the cost of calibration-time optimization.

==== OSTQuant

SpinQuant varies orientation. OSTQuant (Hu et al., 2025) additionally varies *per-channel scale* to improve how transformed tensors occupy the quantization space.

For an invertible $T = R S$ with orthogonal $R$ and nonsingular diagonal $S$,

$
  X W = (X T) (T^(-1) W)
$

Orthogonal mixing redistributes coordinates, whereas scaling adjusts their relative ranges. OSTQuant introduces *Quantization Space Utilization Rate (QSUR)* to assess how efficiently quantized values use the available space.

The paper also proposes a KL-Top objective for retaining important semantic information with limited calibration data.

*Remark:* OSTQuant combines *rotation and scaling*, rather than treating every orthogonal basis as equally quantizable. QSUR and KL-Top are optimization criteria, not a proof that quantization itself is lossless.

=== Quantization-Aware Training (QAT)

PTQ selects a representation for weights after training. QAT instead makes the model *experience quantization error during optimization*, allowing trainable parameters to adapt.

A common fake-quantization forward pass is

$
  y = Q_"fake" (W) x
$

Even though rounding has a zero derivative almost everywhere, the straight-through estimator (STE) may approximate its gradient by

$
  (partial "round" (z)) / (partial z) approx 1
$

within the relevant quantization range. This is an optimization surrogate, not the mathematical derivative of rounding.

==== LLM-QAT

LLM-QAT (Liu et al., 2023) addresses the practical difficulty that large pretraining datasets may not be available when compressing an existing model.

These samples approximate the language distribution on which adaptation should preserve the model's behavior.

Weights, activations, and optionally KV-cache representations are simulated at the target low bit width.

For temperature $tau$, let

$
  p_T = "softmax" (z_T / tau), quad p_S = "softmax" (z_S / tau)
$

and optimize a distillation term of the form

$
  cal(L)_"KD" = tau^2 sum_v p_T (v) log(p_T (v) / p_S (v))
$

alongside any other training objectives used by the implementation.

*Remark:* LLM-QAT adapts a quantized student with *teacher-generated data and predictive supervision*, trading additional training cost for lower-precision fidelity.

==== EfficientQAT

Full end-to-end QAT is expensive for large models. EfficientQAT (Chen et al., 2025) splits optimization into two stages that train different sets of parameters.

For each Transformer block $B_j$, quantize its weights and optimize its local output reconstruction:

$
  min_(theta_j) norm(B_j^"quant" (X_j; theta_j) - B_j^"float" (X_j))_F^2
$

Here $theta_j$ includes the parameters allowed to adapt in that quantized block.

Assemble the quantized blocks, keep the quantized backbone weights fixed, and optimize primarily quantization step sizes using a whole-model objective:

$
  min_s cal(L) (f_"quant" (X; s), f_"target" (X))
$

*Remark:* EfficientQAT first recovers *local block fidelity* and then adjusts *global scale parameters*. The separation lowers training-resource requirements compared with full-model QAT.

==== BitNet

Conventional quantization lowers the precision of a pretrained dense parameterization. BitNet (Wang et al., 2023) designs and trains an architecture around *binary weights* from the outset.

In a simplified sign-binarized form,

$
  hat(W) = alpha "sign" (W)
$

where $alpha$ is an appropriate scale. Training retains higher-precision latent weights while using quantized weights in forward computation.

Forward matrix multiplication uses low-precision representations, while gradients flow through a surrogate quantizer.

*Remark:* BitNet makes extremely low weight precision an *architectural training choice*. It is not equivalent to applying one-bit RTN to an arbitrary pretrained Transformer.

==== BitNet b1.58

Pure binary weights can constrain expressiveness. BitNet b1.58 (Ma et al., 2024) extends the binary representation to *ternary* weights.

The quantizer returns

$
  hat(w) in {-1, 0, 1}
$

up to scaling, instead of only $-1$ and $1$.

Three equally likely states require

$
  log_2 (3) approx 1.58
$

bits of ideal fixed-entropy information per weight. This number is not necessarily the literal physical storage width of a deployed tensor.

Ternary weights permit multiplication-free or simplified arithmetic on suitable integer hardware.

*Remark:* The extra zero state increases modeling flexibility while retaining very low effective precision. Actual memory compression depends on the chosen encoding and kernels.

==== OneBit

BitNet and BitNet b1.58 primarily train a low-bit architecture. OneBit (Xu et al., 2024) instead targets *compression of an existing pretrained model*.

A conceptual one-bit factorization writes a weight approximation as

$
  W approx "diag" (a) B "diag" (b), quad B_(i j) in {-1, 1}
$

This illustrates the sign-scale factorization rather than the full OneBit parameterization

Find a binary representation and associated scale/decomposition parameters that approximate the original full-precision weights.

Fine-tuning recovers performance lost by the aggressive binary constraint.

*Remark:* OneBit is a *post-pretraining binary compression* strategy, conceptually distinct from training BitNet-style low-bit layers from scratch.

==== STBLLM

Even binary weights take roughly one bit each before encoding overhead. STBLLM explores whether *structured sparsity* and ultra-low-bit representation can reduce the average information cost further.

For $N:M$ sparsity, retain only $N$ weights in each group of $M$ positions.

If the nonzero signs are binary and the zero pattern is also stored, an idealized group requires approximately

$
  B_"group" = log_2 binom(M, N) + N
$

bits before additional scales or coding overhead. Dividing by $M$ gives a simplified *average bits-per-original-weight* estimate.

The actual method uses its own structured binary/low-bit parameterization and refinement procedures.

*Remark:* Sub-one-bit averages arise from *sparsity plus compression*, not from encoding two equally likely nonzero signs in less than one bit each. Hardware benefits require suitable sparse kernels.

== Pruning

Quantization keeps most parameters but represents them with fewer bits. *Pruning* removes parameters or computations. Let $W$ be a dense weight matrix and $M$ a binary mask. An unstructured pruned matrix is

$
  hat(W) = M dot.o W, quad M_(i j) in {0, 1}
$

An arbitrary sparse mask may save stored nonzero weights without making dense matrix multiplication faster. *Structured pruning* instead removes complete rows, columns, heads, or blocks so the remaining matrices can become physically smaller.

=== Structured Weight Pruning

==== SliceGPT

SliceGPT (Ashkboos et al., 2024) exploits the fact that a suitable Transformer can express essentially the same full-precision computation in different hidden-state bases.

Let $R in RR^(d times d)$ be orthogonal and define $x^prime = R^T x$. For a linear layer,

$
  W x = (W R) x^prime
$

This change of coordinates does not change the result if the connected operations are consistently transformed. The exact architecture must satisfy the appropriate computational-invariance conditions; arbitrary nonlinear modules cannot be rotated independently.

Use calibration activations to identify directions that carry less information. In a PCA-like view, define the activation covariance

$
  Sigma = 1/N sum_(t=1)^N x_t x_t^T
$

and orient the basis so less important dimensions can be placed together.

Retain only the first $r < d$ coordinates and remove the corresponding weight rows and columns. Unlike zeroing weights with a mask, this produces smaller *dense* matrices.

*Remark:* Rotation itself is information-preserving under the required invariances; *slicing* is the lossy step. The advantage is ordinary dense-kernel execution after compression.

==== LLM-Pruner

A simple weight-magnitude heuristic ignores how a group contributes to language-model loss. LLM-Pruner (Ma et al., 2023) uses gradient information to estimate the importance of *structural groups*.

Attention heads, FFN channels, and their linked rows and columns must often be removed together so the remaining network has valid dimensions.

A first-order Taylor approximation motivates

$
  cal(L) (W+delta W) - cal(L) (W)
  approx (nabla_W cal(L))^T delta W
$

For a group $G$ deleted by $delta W_G = -W_G$, the magnitude of the corresponding first-order term is an inexpensive importance indicator. The actual paper offers group-structured importance and dependency handling beyond this one expression.

Delete low-importance groups, then apply parameter-efficient fine-tuning to restore model quality.

*Remark:* Gradient-informed group importance is more task-aware than pure magnitude pruning, but estimating importance and recovering performance still costs computation.

==== FASP

Deleting one hidden channel usually removes a column from one weight matrix *and* the matching row from its neighboring matrix. FASP addresses this coupled shape constraint.

In a simplified linear composition,

$
  y = W_2 W_1 x
$

remove a consistent set of intermediate coordinates from both $W_1$ and $W_2$.

The aim is to retain the directions that best preserve the layer outputs under a limited channel budget.

For retained features $Z$ and original outputs $Y$, solve

$
  hat(W)_2 = "argmin"_A norm(Y-A Z)_F^2
$

The closed-form least-squares solution, when the inverse exists, is

$
  hat(W)_2 = Y Z^T (Z Z^T)^(-1)
$

*Remark:* FASP removes *consistent intermediate structures* and uses local reconstruction instead of requiring end-to-end retraining. The equations illustrate its shape-preserving least-squares principle.

==== SlimLLM

SlimLLM asks whether two attention heads or FFN channels provide substantially redundant representations, even when their individual magnitudes are large.

For head outputs $H_a$ and $H_b$, a normalized similarity such as

$
  rho_(a b) = ("inner" (H_a,H_b)) / (norm(H_a)_F norm(H_b)_F)
$

can illustrate how correlated two heads are. The paper uses its own head-correlation and selection analysis rather than this being a universal scoring definition.

Greedy selection attempts to preserve diverse attention behavior rather than merely retaining heads with the largest weights.

If $Z$ contains FFN activation observations, the leading singular directions of $Z$ indicate a lower-dimensional space that retains much of the activation variation.

*Remark:* SlimLLM prunes based on *representation redundancy*, with head correlation and PCA-inspired FFN analysis. Calibration distribution and greedy choices affect which components appear dispensable.

=== Unstructured Weight Pruning

==== Wanda

Wanda (Sun et al., 2023) combines weight magnitude with how strongly the corresponding input channel is activated.

Let $Y = W X$, where each row of $X$ records one input feature across calibration tokens.

Removing $W_(i j)$ changes output coordinate $i$ by

$
  delta Y_i = -W_(i j) X_(j,:)
$

Therefore its output-error norm is exactly

$
  norm(delta Y_i)_2 = abs(W_(i j)) norm(X_(j,:))_2
$

This motivates Wanda's importance score

$
  s_(i j) = abs(W_(i j)) norm(X_(j,:))_2
$

with selection commonly performed under local sparsity constraints.

*Remark:* Wanda's metric follows directly from a *single-weight output perturbation*. It is simple and retraining-free, but does not explicitly account for interactions among many simultaneously removed weights.

==== SparseLLM

Independent layerwise pruning may lose accuracy because errors propagate and interact across layers. SparseLLM uses an optimization-based approach with auxiliary variables to account for network-wide behavior.

With layer weights $W_l$ and masks $M_l$,

$
  hat(W_l) = M_l dot.o W_l
$

An abstract objective is

$
  min_(M_1,dots,M_L) cal(L) (f_(hat(W_1),dots,hat(W_L)))
$

subject to a global budget such as

$
  sum_l norm(M_l)_0 <= B
$

SparseLLM employs auxiliary variables and soft penalties to make global optimization more tractable, then refines sparsity decisions iteratively.

*Remark:* The main change from Wanda is *joint optimization under a global objective*. The stated constrained program is a conceptual target, not a claim that the discrete problem is solved exactly.

==== OPTISHEAR

A single fixed importance score is not necessarily optimal at all sparsity levels. OPTISHEAR searches for effective *weight-and-activation-based importance metrics* and evaluates their output-reconstruction trade-offs.

Schematically, one may consider a family

$
  s_(i j)(alpha,beta)
  = abs(W_(i j))^alpha norm(X_(j,:))_2^beta
$

which includes magnitude-only and activation-aware preferences. This formula illustrates a tunable family; it is not intended to reproduce all the metric candidates in the paper.

For each candidate score and sparsity level, retain the most important weights under the desired pruning pattern.

For calibration output $Y$, evaluate errors such as

$
  cal(E) (M) = norm(Y - (M dot.o W) X)_F^2
$

and search for a favorable error-sparsity configuration.

*Remark:* OPTISHEAR is *importance-metric optimization*, not simply another fixed magnitude rule. Search cost is paid during compression, while irregular inference sparsity may still need custom kernels.

=== Activation Sparsity and Calibrated Pruning

Weight pruning removes connections from the model. *Activation sparsity* instead aims to make computations vanish for particular inputs. With an FFN hidden vector $h$ and input-dependent mask $m(x)$,

$
  hat(h)(x) = m(x) dot.o h(x)
$

A fixed threshold can still produce different masks for different tokens. It is therefore essential to distinguish *fixed parameters* from *fixed activation patterns*.

==== SCAP

SCAP (Chua et al., 2024) increases activation sparsity after training by calibrating activation distributions.

Many activations cluster around a mode $mu_j$ that need not equal zero.

A schematic sparsifier is

$
  hat(h_j) = (h_j-mu_j) bold(1)_(abs(h_j-mu_j) > tau_j)
$

where $bold(1)_("condition")$ denotes an indicator. In an actual layer, any induced shift must be compensated as appropriate to preserve the surrounding affine computation.

Use a small representative sample to choose $tau_j$ or layerwise thresholds, then use sparse execution during inference.

*Remark:* SCAP makes more activations skippable through *post-training statistical calibration*. Thresholds can be fixed while the locations of zero activations remain input-dependent.

==== ProSparse

A SwiGLU FFN often produces few exact zeros, so a sparse kernel cannot skip much work. ProSparse modifies the activation and training procedure to create more genuine zeros.

For example,

$
  "ReLU" (z) = max(0, z)
$

is zero for all negative inputs, unlike SiLU.

A schematic objective is

$
  cal(L) = cal(L)_"LM" + lambda cal(R)_"sparse" (h)
$

where the penalty and threshold schedule encourage low-importance activations to become zero.

If an FFN's intermediate vector has many zeros, sparse matrix-vector kernels may avoid the corresponding multiplications.

*Remark:* ProSparse *trains for activation sparsity* rather than assuming it already exists. Zero locations still vary with the input, and realized speedups require efficient sparse execution.

==== SEAP

SEAP (Liang et al., 2025/2026) observes that different tasks activate different subsets of model neurons. The method therefore seeks *task-specific expert activation paths* rather than one universal static mask.

Use a multi-task calibration dataset to cluster hidden-state and neuron-activation patterns associated with different tasks.

For task label or latent expert $e$, write a mask $m_e$ representing the computation path estimated to be useful.

A lightweight task router chooses $e(x)$, giving the schematic computation

$
  hat(h)(x) = m_(e(x)) dot.o h(x)
$

The mask bank is learned or calibrated beforehand, but the chosen path is input-dependent.

*Remark:* SEAP is a *task-aware structured activation-path selection* method with routing. It should not be misrepresented as one fixed global mask selected once for all inputs.

==== R-Sparse

Simply discarding weak activations introduces output bias, because even small omitted components can accumulate. R-Sparse couples activation selection with low-rank information and compensating terms.

For $y = W h$ and a selection mask $m$,

$
  y = W (m dot.o h) + W ((1-m) dot.o h)
$

If omitted activations concentrate around a calibration mean $mu$, use the correction

$
  y approx W (m dot.o h) + W ((1-m) dot.o mu)
$

as a motivating constant-compensation case. R-Sparse additionally uses low-rank contribution information; its algorithm is more general than this single mean-substitution identity.

Input-independent correction terms can be absorbed into biases, while low-rank or sparse residual operations capture the remaining variation.

*Remark:* R-Sparse does not assume that every removed activation contributes exactly zero. It targets a better approximation using *contribution estimates and compensation*.

=== Runtime-Dependent Activation and Attention Pruning

A global sparsity pattern may not suit every prompt or batch. Runtime-dependent methods estimate which tokens, channels, or attention interactions matter *for the current input*, paying additional selection cost for more targeted computation.

==== Sparse Flash Attention

The phrase "FlashAttention" by itself means *exact dense attention with efficient memory I/O*. Sparse Flash Attention refers here to methods that introduce *approximate sparse interaction patterns* in addition to GPU-aware execution.

For query $i$, let $cal(N) (i)$ denote selected key indices, for example from query-key dropping or locality-sensitive hashing.

The sparse attention output is

$
  y_i = (sum_(j in cal(N) (i)) exp(q_i^T k_j / sqrt(d)) v_j)
  / (sum_(j in cal(N) (i)) exp(q_i^T k_j / sqrt(d)))
$

Block structure, grouping, and kernel implementation determine whether savings exceed selection overhead.

*Remark:* Sparse attention reduces *which pairs interact*, while ordinary FlashAttention preserves all pairs and changes only their execution. Missing a relevant pair is a model approximation, not a numerical rearrangement.

==== Probe Pruning

Probe Pruning (Le et al., 2025) avoids making every batch use the same pruned weights.

Choose representative hidden states, advance them through a small amount of computation, and estimate which channels are valuable.

Fuse current-batch evidence with statistics collected from earlier batches to stabilize the importance estimate.

For the current batch $B$, write

$
  M_B = "Select" ("Probe" (B), "History")
$

and use the retained weight channels for full-batch inference.

*Remark:* Probe Pruning trades a small amount of *adaptive inspection* for more accurate batch-specific structured pruning. It is not a universal fixed pruning mask, and the probe must be cheap relative to the saved work.

== Knowledge Distillation

Pruning and quantization restrict the original model's computation. *Knowledge distillation (KD)* trains a student to reproduce information supplied by a teacher, potentially enabling a smaller or quantized architecture to recover quality.

Let $p_T (v | x)$ and $p_S (v | x)$ denote teacher and student token distributions. Standard distribution-level distillation minimizes a forward KL divergence

$
  "KL" (p_T, p_S)
  = sum_v p_T (v|x) log(p_T (v|x) / p_S (v|x))
$

Because the teacher distribution does not depend on student parameters, minimizing this is equivalent to minimizing soft-label cross entropy. A student can also learn from teacher hidden states, generated answers, or intermediate reasoning.

=== White-Box Methods

White-box distillation assumes access to at least some teacher logits or internal representations. The following methods differ mainly in *what information is matched*, *which loss is used*, and *which sequences are used for supervision*.

==== BabyLLaMA

A single teacher may be biased toward its own architecture or token predictions. BabyLLaMA (Timiryasov and Tastet, 2023) uses knowledge from multiple small language-model teachers.

For teacher $m$, let $p_m (v|x)$ be its next-token distribution.

An illustrative probability ensemble is

$
  bar(p)_T (v|x) = sum_(m=1)^M alpha_m p_m (v|x),
  quad sum_m alpha_m = 1
$

The aggregation is schematic: probability and logit ensembles are not interchangeable

Minimize soft-label cross entropy

$
  cal(L) = -sum_v bar(p)_T (v|x) log p_S (v|x)
$

*Remark:* Multiple teachers can supply complementary supervision, but ensemble predictions are more costly to collect and potentially inconsistent.

==== Task-aware TED

Distilling every hidden dimension assumes that all internal teacher features matter to the downstream task. Task-aware TED (Liang et al., 2023) learns filters that emphasize the task-relevant portions.

For corresponding layers, denote them $H_T$ and $H_S$.

Let $F_T$ and $F_S$ be lightweight trainable filters. Define

$
  Z_T = F_T (H_T), quad Z_S = F_S (H_S)
$

A schematic alignment objective is

$
  cal(L)_"feature" = norm(Z_T-Z_S)_F^2
$

The filters are trained to preserve information relevant to downstream predictions rather than force identical raw hidden states.

*Remark:* TED distills *task-relevant transformed features*, reducing the burden of matching every latent coordinate. The filters themselves require training.

==== Token-Scaled Logit Distillation (TSLD)

Standard KD weights each supervised token equally. TSLD (Kim et al., 2023) observes that teacher confidence differs across positions, especially when training a quantized student.

At position $t$ with target $y_t$,

$
  c_t = -log p_T (y_t | x_(<t))
$

A larger $c_t$ means lower teacher confidence in the correct next token.

With temperature $tau$,

$
  w_t = exp(c_t/tau) / (sum_u exp(c_u/tau))
$

$
  cal(L)_"TSLD"
  = -sum_t w_t sum_v p_T^(t) (v) log p_S^(t) (v)
$

*Remark:* TSLD emphasizes *low-confidence teacher positions* rather than giving every token equal influence. Its confidence is measured using teacher cross entropy against the ground truth, not just the maximum teacher probability.

==== MiniLLM

Forward KL penalizes the student for assigning insufficient probability to teacher-supported outcomes. For a limited-capacity student, covering every teacher mode may be difficult. MiniLLM (Gu et al., 2024) studies the reverse direction.

$
  "FKL" = sum_v p_T (v) log(p_T (v) / p_S (v))
$

$
  "RKL" = sum_v p_S (v) log(p_S (v) / p_T (v))
$

Under forward KL, failing to cover a teacher-probable region is costly. Under reverse KL, probability assigned to regions disliked by the teacher is costly; this can encourage a more concentrated student approximation.

MiniLLM additionally develops estimation and generation techniques appropriate to autoregressive models, rather than merely swapping the two symbols in a static loss.

*Remark:* Reverse KL changes the *mode-covering versus mode-seeking* behavior. It may improve quality under capacity limits, but can underrepresent low-probability teacher modes.

==== Generalized Knowledge Distillation (GKD)

A student trained only on teacher-forced prefixes may behave differently at deployment, where its inputs include its own earlier mistakes. GKD (Agarwal et al., 2023) targets this *distribution mismatch*.

With prompt $x$ and student policy $p_S$,

$
  y tilde.op p_S (dot | x)
$

The resulting prefixes are representative of what the student encounters during inference.

Compare $p_T (dot|x,y_(<t))$ with $p_S (dot|x,y_(<t))$ at positions of the student-generated sequence.

A conceptual objective is

$
  cal(L)_"GKD"
  = EE_(y tilde.op p_S (dot|x))
  [sum_t D(p_T (dot|x,y_(<t)), p_S (dot|x,y_(<t)))]
$

where $D$ can be selected to suit the student. The framework can also be combined with reinforcement-learning fine-tuning.

*Remark:* GKD changes *where training examples come from*: the student generates the sequences on which the teacher provides feedback. It is not confined to a single fixed KL direction.

==== DistiLLM

On-policy distillation helps reduce exposure mismatch but requires expensive repeated generation. DistiLLM (Ko et al., 2024) improves both the *divergence* and the *reuse of student-generated data*.

Let

$
  m_alpha = alpha p_T + (1-alpha) p_S
$

The skewed forward divergence is

$
  D_"SKL"^alpha (p_T,p_S)
  = "KL" (p_T, m_alpha)
$

A corresponding skewed reverse form can use a mixture inside the denominator of a student-to-mixture KL. Placing nonzero teacher mass inside $m_alpha$ limits extreme penalties when the student assigns almost zero probability to a teacher-supported token.

Instead of always sampling fresh sequences, retain suitable previous generations.

Update the student using both fresh and reusable data while monitoring their relevance to the current student distribution.

*Remark:* DistiLLM combines *skewed divergence for stable optimization* with *adaptive off-policy reuse for cheaper training*. It is not simply temperature-scaled ordinary KL.

==== Dual-Space Knowledge Distillation (DSKD)

When a teacher and student have different hidden dimensions or vocabularies, directly matching their logits is not well-defined. DSKD (Zhang et al., 2024) makes both models comparable in *two output spaces*.

Let teacher and student hidden states be $H_T in RR^(n_T times d_T)$ and $H_S in RR^(n_S times d_S)$. Introduce projection matrices

$
  P_(T -> S) in RR^(d_T times d_S),
  quad P_(S -> T) in RR^(d_S times d_T)
$

With corresponding output matrices $W_T$ and $W_S$, a simplified same-tokenization construction is

$
  p_(T -> S) = "softmax" (H_T P_(T -> S) W_S)
$

$
  p_(S -> T) = "softmax" (H_S P_(S -> T) W_T)
$

These distributions allow comparisons in the student's or teacher's own vocabulary space.

Cross-model attention learns an alignment matrix $A in RR^(n_S times n_T)$ between teacher and student token positions, so that projected teacher features can be compared with the student sequence:

$
  hat(H)_(T -> S) = A H_T P_(T -> S)
$

The original method combines teacher-space and student-space distillation losses with a cross-entropy term.

*Remark:* DSKD addresses both *representation-space discrepancy* and *token alignment*. Its central idea is more precise than merely comparing differently sized logits after an arbitrary linear projection.

==== BitDistiller

Low-bit students may be unable to match every teacher probability equally well. BitDistiller (Du et al., 2024) combines low-bit weight adaptation with confidence-aware divergence selection.

Let $p_T$ be the full-precision teacher distribution and $p_S$ the quantized student distribution.

An abstract confidence-aware divergence is

$
  cal(L)_"CAKLD" = beta "KL" (p_S,p_T)
  + (1-beta) "KL" (p_T,p_S)
$

where the mixture weight $beta$ depends on model confidence. The original implementation's confidence calculation, clipping, and masking determine the exact reduction.

The quantization algorithm and its asymmetric low-bit weight treatment are part of the method; the divergence is not a stand-alone replacement for PTQ.

*Remark:* BitDistiller combines *asymmetric low-bit optimization* and *confidence-aware balancing of KL directions*. It is incorrect to describe CAKLD as a forward KL merely multiplied by one confidence scalar.

==== Centered Kernel Alignment (CKA) Distillation

Direct feature regression assumes teacher and student representations share coordinates. If their hidden sizes differ, matching *pairwise relations among examples* can be more meaningful.

For teacher and student features, compute Gram matrices

$
  K = H_T H_T^T, quad L = H_S H_S^T
$

Both matrices have shape $n times n$, even if the teacher and student hidden widths differ.

With $C = I - bold(1) bold(1)^T/n$,

$
  K_c = C K C, quad L_c = C L C
$

The linear-kernel CKA similarity is

$
  "CKA" (K,L)
  = "tr" (K_c L_c)
  / sqrt("tr" (K_c^2) "tr" (L_c^2))
$

A distillation loss can minimize $1-"CKA" (K,L)$.

*Remark:* CKA transfers *representational geometry* rather than raw feature coordinates. It accommodates unequal hidden widths but requires forming or approximating pairwise similarity information.

==== Speculative Knowledge Distillation

Pure teacher-generated training data may not represent the student's actual mistakes. Fully student-generated data can require costly teacher evaluation at every step. Speculative KD uses *student proposals with selective teacher intervention*.

At a generation step, compute a student confidence measure such as

$
  c_t = max_v p_S (v | x_(<t))
$

This illustrates a possible confidence test; the original paper's thresholding and collaborative generation details determine the actual policy.

The teacher is used more heavily where student predictions are judged unreliable.

Use the teacher-supervised outcomes to adapt the student on sequences closer to its own generation behavior.

*Remark:* Speculative KD focuses teacher compute on informative uncertain steps. The resulting speed benefit is during *training data generation*, not automatically in the student's inference kernel.

=== Black-Box and Grey-Box Methods

If the teacher is accessible only through an API returning text, its logits and hidden states may be unavailable. Black-box distillation relies on *observable outputs*; grey-box methods may construct an accessible surrogate for distributional supervision.

==== Multitask In-Context Tuning

A large prompted teacher can generate examples for many tasks without exposing internal features.

For task $k$, use demonstrations $D_k$ to obtain output $y_T$ from the teacher.

The student training set becomes

$
  cal(D) = {(x_i,k_i,y_(T,i))}_i
$

Jointly tune the student. A simple multi-task objective is

$
  cal(L) = -sum_(i,t) log p_S (y_(T,i,t) | x_i,k_i,y_(T,i,<t))
$

possibly combined with language-modeling losses.

*Remark:* The transferred signal is *teacher behavior under prompting*. A text-only API does not give full teacher probability distributions merely because outputs are generated from a probabilistic model.

==== Distilling Step-by-Step

A single final answer gives weak supervision for a multi-step reasoning problem. Distilling Step-by-Step (Hsieh et al., 2023) adds teacher-generated rationales.

Collect triples $(x,r,y)$.

An illustrative objective is

$
  cal(L) = -log p_S (r|x) -log p_S (y|x,r)
$

or an equivalent combined target-sequence loss.

Learning to produce a plausible chain of text does not necessarily prove faithful reasoning.

*Remark:* Rationales provide *intermediate training targets* that are absent from answer-only labels. Their usefulness depends on the correctness and relevance of the teacher's reasoning traces.

==== Fine-tune-CoT

Instead of requesting only one reasoning path, Fine-tune-CoT (Ho et al., 2022) generates *diverse* teacher rationales and filters them by answer correctness.

For prompt $x$, collect

$
  {(r_j,y_j)}_(j=1)^M tilde.op p_T (dot|x)
$

Keep examples for which the final answer $y_j$ matches a trusted answer $y^*$, giving a selected set $cal(D)_"valid"$.

$
  cal(L) = -sum_((x,r,y) in cal(D)_"valid") log p_S (r,y|x)
$

*Remark:* Sampling and answer-based filtering improve diversity and reduce obvious errors. Correct final answers do not guarantee every retained intermediate step is logically sound.

==== Lion

Passive imitation does not tell the student which behaviors it currently finds most difficult. Lion (Jiang et al., 2023) introduces an adversarially constructed training-data loop.

On a prompt set $cal(D)$,

$
  cal(L)_"imitate" = -sum_(x,y_T) log p_S (y_T|x)
$

A referee model or evaluator scores candidate instructions according to student weakness.

A generator uses the referee feedback to create hard examples; the teacher labels them, and the student is trained again.

*Remark:* Lion changes *data selection and generation* through an adversarial loop. The method's value depends on the quality of generated challenges and referee judgments.

==== DiSCo

Some distillation tasks concern representations rather than text generation. DiSCo is a *retrieval-oriented* example that transfers teacher guidance into a smaller dense retriever.

Obtain alternative queries $q^+$ that better expose a document's intended relevance.

Let

$
  s(q,d) = f_q (q)^T f_d (d)
$

be their retrieval similarity.

For positive document $d^+$ and negatives $d^-_j$,

$
  cal(L)_"retrieval"
  = -log (exp(s(q,d^+)/tau)
    / (exp(s(q,d^+)/tau)+sum_j exp(s(q,d^-_j)/tau)))
$

This equation describes the standard contrastive training mechanism, rather than claiming it reproduces every detail of DiSCo's objectives.

*Remark:* DiSCo distills *retrieval behavior* through teacher-assisted queries. It should not be presented as a general language-model architecture compression algorithm.

==== Counterfactual-Explanation-infused Distillation (CoD)

Examples far from a decision boundary may teach little about where the student should change its prediction. Counterfactual distillation supplies *nearby examples with contrasting outcomes*.

Let the teacher predict $y = f_T (x)$.

Find $x^prime$ that changes the teacher's decision while preserving validity:

$
  min_(x^prime) d(x,x^prime)
$

subject to

$
  f_T (x^prime) != f_T (x)
$

Here $d$ measures perturbation size, and additional task-specific feasibility constraints are needed.

The student learns both the expected prediction and the local decision contrast.

*Remark:* Counterfactual supervision clarifies *local decision boundaries*. Its value depends on whether the generated counterfactuals are valid, realistic, and correctly evaluated.

==== Proxy-KD (Grey-Box)

A black-box teacher exposes hard outputs but not the full distribution required for logit KD. Proxy-KD (Chen et al., 2024) constructs an accessible proxy to approximate that missing information.

Use the black-box answers as preferred behavior, with training that may combine answer likelihood and preference-style objectives.

For the accessible proxy $p_P (v|x)$, full next-token distributions are available.

The student can minimize

$
  cal(L) = -lambda log p_S (y_T|x)
  + (1-lambda) "KL" (p_P (dot|x),p_S (dot|x))
$

where $y_T$ is the black-box answer. The exact training schedule and coefficients are method-dependent.

*Remark:* Proxy-KD constructs *distribution-like supervision* from a black-box model without claiming that the proxy logits equal the inaccessible teacher logits. Proxy alignment error and API costs remain important.

== Approximation

Quantization reduces numerical precision, whereas approximation replaces a computation by a cheaper mathematical representation. Two major cases are *low-rank matrix factorization* and *approximation of nonlinear operators*. Approximate attention should not be confused with compressing a weight matrix: the former changes token interactions, while the latter changes the parameter representation.

=== Low-Rank Linear Approximation

For a matrix $W in RR^(m times n)$ with singular value decomposition

$
  W = U Sigma V^T = sum_(i=1)^p sigma_i u_i v_i^T
$

where $p = min(m, n)$ and $sigma_1 >= sigma_2 >= dots >= sigma_p >= 0$, the rank-$r$ truncated approximation is

$
  W_r = U_r Sigma_r V_r^T
$

By the Eckart-Young theorem, $W_r$ minimizes $norm(W-hat(W))_F$ among rank-$r$ matrices. Its parameter storage can fall from $m n$ to approximately $r(m+n)$ by absorbing $Sigma_r$ into one factor.

However, *best weight-space approximation* need not be the best *network-output approximation*. This motivates the following variants.

==== Fisher-Weighted SVD (FWSVD)

An ordinary SVD treats every weight-space direction uniformly. FWSVD uses Fisher-information-based importance to prioritize directions most relevant to the model loss.

The Fisher information matrix takes the conceptual form

$
  F = EE_((x,y)) [g g^T], quad g = "vec" (nabla_W log p(y|x;W))
$

where in practice the full matrix is usually too large and must be approximated.

A local quadratic loss approximation suggests

$
  delta cal(L) approx 1/2 "vec" (delta W)^T F "vec" (delta W)
$

Rather than minimizing ordinary Frobenius error, prioritize reconstruction directions with larger Fisher sensitivity.

Scale or reweight the matrix according to the estimated importance, perform low-rank decomposition, and transform back as required.

*Remark:* FWSVD preserves *task-sensitive directions* rather than just those with the largest singular values. Estimating a useful Fisher weighting can itself be expensive.

==== Activation-aware SVD (ASVD)

The optimal truncated SVD of $W$ ignores the distribution of input activations. ASVD (Yuan et al., 2024) uses calibration statistics to make the factorization aware of typical layer inputs.

For $Y = W X$, minimize

$
  min_("rank" (hat(W)) <= r) norm((W-hat(W)) X)_F^2
$

rather than just $norm(W-hat(W))_F^2$.

If $S$ is a diagonal matrix describing the important input directions, factorize $W S$:

$
  W S approx U_r Sigma_r V_r^T
$

Then reconstruct

$
  hat(W) = U_r Sigma_r V_r^T S^(-1)
$

This is an approximate approach to the activation-weighted objective; diagonal scaling need not reproduce the full input covariance.

Compress more aggressively where layers are empirically less sensitive and retain larger ranks elsewhere.

*Remark:* ASVD is still a *weight-matrix approximation*, but it measures which directions matter using *layer inputs*. The quality of calibration scales and layerwise rank allocation is crucial.

==== LoRD

Not every linear layer benefits equally from low-rank factorization. For an $m times n$ matrix, replacing it with rank-$r$ factors is a parameter reduction only if

$
  r(m+n) < m n
$

If $r$ must remain large relative to $min(m, n)$ to preserve quality, factorization may save little memory or even add computational overhead.

Select suitable layers. LoRD uses layer structure and compression benefit to identify where low-rank decomposition is worthwhile.

Other layers remain dense so that small theoretical savings do not impose unnecessary extra matrix multiplications.

*Remark:* LoRD emphasizes *where* to factorize, not just *how* to compute the truncated SVD. Layer selectivity improves efficiency but limits maximum compression.

==== SVD-LLM

The unweighted SVD objective can choose the wrong subspace for actual activations. SVD-LLM (Wang et al., 2024) uses *input whitening* and sequential recovery.

For calibration inputs $X$,

$
  Sigma_X = X X^T / N
$

Whiten the input geometry. Choose an invertible transform $S$ related to the covariance so that the transformed inputs have a more balanced distribution. The output reconstruction objective can then be expressed through the singular values of an appropriately transformed weight matrix.

With the convention that $S$ acts on the input dimension,

$
  W S approx U_r Sigma_r V_r^T,
  quad hat(W) = U_r Sigma_r V_r^T S^(-1)
$

The actual whitening convention can be written using inverse factors instead; consistency between the transformed inputs and weights is what matters.

SVD-LLM uses low-rank adaptation in a sequential recovery procedure to reduce degradation accumulated across compressed layers.

*Remark:* SVD-LLM aligns the truncated SVD with *activation-induced output error*, then uses targeted recovery. Whitening depends on reliable calibration statistics.

==== SoLA

FFNs may contain a small number of highly influential neurons and a large collection of weaker, redundant components. Compressing all channels uniformly may remove the wrong information.

Use activation statistics to isolate neurons whose contribution should be preserved more faithfully.

Conceptually,

$
  W = W_"important" + W_"remainder"
$

where the first part contains the selected important structure and the second is the candidate for low-rank approximation.

$
  hat(W) = W_"important" + U_r Sigma_r V_r^T
$

Different modules can use different ranks depending on their measured sensitivity.

*Remark:* SoLA combines *selective preservation of important neurons* with *low-rank compression of the rest*. It is a calibration-based decomposition strategy rather than blind global rank truncation.

==== SVD-LLM V2

Using the same rank for every layer ignores variation in the cost of truncating its singular directions. SVD-LLM V2 allocates compression capacity using analytical error estimates and optimized factors.

In ordinary SVD, the squared Frobenius truncation error is

$
  norm(W-W_r)_F^2 = sum_(i=r+1)^p sigma_i^2
$

For model compression, this estimate is adapted to the transformed or activation-aware reconstruction loss rather than taken as a universal prediction of task accuracy.

With estimated layer truncation costs $E_l (r_l)$ and a global parameter budget $B$, solve a resource-allocation problem of the form

$
  min_(r_1,dots,r_L) sum_l E_l (r_l)
$

subject to

$
  sum_l r_l (m_l+n_l) <= B
$

Direct factor optimization or reconstruction refinement improves the chosen low-rank model.

*Remark:* SVD-LLM V2 improves *rank allocation and factor recovery*, rather than assuming one uniform compression ratio across every layer. Analytical truncation errors remain proxies for downstream quality.

=== Nonlinear Approximation

The standard softmax of scores $s_1,dots,s_n$ is

$
  p_i = exp(s_i) / (sum_j exp(s_j))
$

For numerical stability, one can subtract $m = max_j s_j$:

$
  p_i = exp(s_i-m) / (sum_j exp(s_j-m))
$

The maximum reduction, exponentials, denominator reduction, and division can all be expensive in specialized hardware. The following proposals approximate or reorganize these steps in different ways.

==== Softermax

Softermax (Stevens et al., 2021) targets the cost of softmax hardware by replacing the base of its exponential and using an online normalization algorithm.

Define a normalized alternative

$
  p_i^prime = 2^(s_i) / (sum_j 2^(s_j))
$

This changes the effective temperature of the function unless logits are rescaled by $log_2 e$.

Given a running maximum $m$ and sum $z$, when a new score $s$ arrives define

$
  m^prime = max(m, s)
$

$
  z^prime = z 2^(m-m^prime) + 2^(s-m^prime)
$

Thus, the denominator can be accumulated incrementally without a separate first pass over all logits.

Base-two exponentiation and rescaling lend themselves to specialized circuits.

*Remark:* Softermax primarily optimizes *softmax hardware implementation*. It should not be conflated with linear attention, and replacing $exp$ by $2^x$ changes the distribution unless input scaling compensates.

==== Power-of-Two Softmax Approximation

A related hardware-oriented approach approximates base-two exponentials using shifts and a low-cost approximation to the fractional exponent.

For $x = n+f$ with integer $n$ and $0 <= f < 1$,

$
  2^x = 2^n 2^f
$

For example, the straight-line interpolant joining the endpoints is

$
  2^f approx 1+f
$

This illustrative approximation is not the only possible fitted function and has a nonzero approximation error inside the interval.

The costly nonlinear calculation is largely replaced by integer arithmetic plus a small fractional calculation.

*Remark:* Power-of-two approximation targets *FPGA/ASIC arithmetic costs*. Whether it helps on general-purpose GPUs depends on available native exponential instructions and numerical-error requirements.

==== ConSmax

Ordinary softmax couples every probability to all logits through a data-dependent denominator. ConSmax (Liu et al., 2024) replaces expensive data-dependent normalization operations with *learnable normalization parameters*.

Standard stabilized softmax requires

$
  m = max_j s_j, quad z = sum_j exp(s_j-m)
$

An illustrative form is

$
  hat(p)_i = exp(s_i-beta) / gamma
$

where $beta$ and $gamma$ are learned or calibrated parameters under the proposed design. This is a *schematic explanation* of the constant-normalizer idea, not a guarantee that $sum_i hat(p)_i = 1$ for arbitrary logits.

Avoiding a maximum search and denominator reduction enables more parallel and hardware-friendly processing.

*Remark:* ConSmax replaces *data-dependent normalization* by learned quantities, trading exact probability normalization for hardware efficiency. The published evidence centers on specialized hardware and relatively small language models.

==== Adaptive Top-k Softmax

When the vocabulary or candidate set is large, a small subset of logits often accounts for most of the probability mass. Adaptive Top-$k$ Softmax uses that concentration to avoid equal processing of all entries.

Let $cal(T)_k$ contain the selected high-score candidates.

A top-$k$ renormalization gives

$
  hat(p)_i = cases(
    exp(s_i)/(sum_(j in cal(T)_k) exp(s_j)) & i in cal(T)_k,
    0 & i in.not cal(T)_k
  )
$

This is the simplest *truncated-softmax illustration*; adaptive sampling algorithms need not literally compute this expression or assign zero probability to every unselected item.

An adaptive strategy uses more candidates when the distribution is diffuse and fewer when it is concentrated.

*Remark:* Adaptive selection can save work in a large output vocabulary, but candidate discovery costs time and omitted probability mass creates approximation error.

==== LoLCATs

Replacing a pretrained LLM's softmax attention with linear attention immediately often destroys model quality. LoLCATs (Zhang et al., 2024) treats conversion as *an approximation-learning problem followed by low-rank recovery*.

For an existing attention layer, compute

$
  Y_"softmax" = "softmax" (Q K^T / sqrt(d)) V
$

A trainable feature map $phi_theta$ gives

$
  Y_"linear" (theta)
  = D_theta^(-1) phi_theta(Q)
  (phi_theta(K)^T V)
$

where $D_theta$ is the associated normalization matrix. Train the feature map to minimize attention-output error:

$
  min_theta norm(Y_"linear" (theta)-Y_"softmax")_F^2
$

For a projection matrix $W$, use

$
  W^prime = W + B A,
  quad A in RR^(r times d_"in"),
  quad B in RR^(d_"out" times r)
$

The low-rank updates recover language-model quality lost when attention is replaced.

*Remark:* LoLCATs *transfers pretrained softmax behavior into learned linear attention* and repairs the remaining errors with LoRA. It is an architecture-conversion method, not just another static feature-map formula.

== Parameter Sharing

Compression can also reduce the number of *distinct* parameter tensors. For $L$ layers with independent weights $W_1,dots,W_L$, storage includes all $L$ copies. If all layers reuse one $W$, unique storage falls substantially even though the layer operation is still evaluated $L$ times.

=== ALBERT

ALBERT (Lan et al., 2020) separates the vocabulary embedding dimension from hidden width and shares Transformer-layer parameters.

For vocabulary size $V$, embedding width $d_e$, and model width $d$,

$
  E in RR^(V times d_e), quad P in RR^(d_e times d)
$

The embedding for token $i$ is $E_i P$. Parameters fall from about $V d$ to $V d_e+d_e d$ if $d_e << d$.

Instead of $h_(l+1) = F_l (h_l)$ with independent $F_l$, use

$
  h_(l+1) = F_"shared" (h_l)
$

*Remark:* ALBERT reduces *unique embedding and layer parameters*, not the number of Transformer evaluations. Aggressive sharing constrains layer specialization.

=== Subformer

Uniform cross-layer sharing can hurt generation because shallow and deep layers perform different jobs. Subformer (Reid et al., 2021) shares the *interior* more aggressively than the boundaries.

A schematic depth layout is

$
  F_"input", F_"shared", dots, F_"shared", F_"output"
$

The first and last layers retain distinct weights while the central layers reuse the same parameters.

Self-Attentive Factorized Embeddings (SAFE) uses a lower-dimensional embedding representation and a lightweight attention-based transformation, particularly in the sequence-to-sequence setting.

The shared interior acts as a repeatedly applied representation learner; unique boundary layers help adapt its input/output behavior.

*Remark:* Subformer combines *where to share depth-wise* and *how to factorize embeddings*. SAFE is not merely ordinary static low-rank embedding projection.

=== Basis Sharing

Complete weight tying is restrictive because every layer must use identical matrices. Basis sharing instead stores a *small common dictionary* of weight components and lets each layer combine them differently.

Let $B_1,dots,B_r in RR^(m times n)$.

$
  W_l approx sum_(j=1)^r a_(l j) B_j
$

This schematic construction stores approximately

$
  P_"shared" = r m n + L r
$

rather than $L m n$, if the full basis matrices and scalar coefficients are all stored directly. It is useful when $r << L$ and the basis representation is efficient; practical papers may use more economical basis factorizations.

*Remark:* Basis sharing trades *complete equality across layers* for *layer-specific combinations of shared components*. Shared storage can remain large if too many full-sized basis matrices are retained.

=== MobileLLM

At sub-billion parameter scale, merely shrinking width can harm representational power. MobileLLM (Liu et al., 2024) favors *deep-and-thin* decoder designs and several parameter-efficient modules.

A rough dense FFN parameter count per layer scales as $O(d^2)$ for an intermediate width proportional to $d$. Under a fixed budget, reducing $d$ can make extra depth affordable.

MobileLLM uses design choices such as embedding sharing, grouped-query attention, and gated FFNs, each targeting a different cost.

MobileLLM-LS ties weights between neighboring blocks. For a pair of adjacent layers, a simplified notation is

$
  h_(l+1) = F_W (h_l),
  quad h_(l+2) = F_W (h_(l+1))
$

The two transformations are executed separately but reuse the same weight parameters.

*Remark:* *MobileLLM and MobileLLM-LS are distinct configurations.* Deep-and-thin design improves the efficiency of small models; adjacent-layer sharing offers an additional storage reduction.

=== MobiLLaMA

The FFN often contributes more parameters than normalization or other small modules. MobiLLaMA targets this large component through cross-layer sharing.

Different layers may retain their own attention parameters.

For instance,

$
  h_(l+1) = h_l + "FFN"_"shared" ("Norm"_l (h_l))
$

is a schematic residual sublayer with layer-specific input states and a common FFN.

Repeated use of the same FFN reduces unique stored weights while still enabling different outputs at different depths because its inputs differ.

*Remark:* MobiLLaMA targets the *dominant FFN parameter budget* without forcing every component to share weights. The cost of FFN execution remains present at each depth.

=== Relaxed Recursive Transformers

Strict parameter sharing makes two depth positions implement the same function. Relaxed Recursive Transformers (Bae et al., 2025) keep a *shared block* but give each invocation its own small low-rank correction.

In the strictly recursive form,

$
  h_(l+1) = F (h_l; W_"shared")
$

For invocation $l$, use

$
  W_l = W_"shared" + B_l A_l
$

where the rank of $B_l A_l$ is small relative to the original matrix dimensions.

If original layer weights are $W_l^"original"$, a natural residual target is

$
  Delta W_l = W_l^"original" - W_"shared"
$

A truncated decomposition of these residuals provides an initialization for the layer-specific updates, followed by additional adaptation.

*Remark:* Relaxed recursion preserves most *storage benefits of sharing* while recovering some *depth-specific specialization*. The original work also studies inference opportunities from recursive depth and early exit; those throughput benefits require suitable scheduling.

= Practical Comparison

The right optimization depends on *which resource is limiting inference*. These methods are not interchangeable: some reduce memory storage, some reduce arithmetic, and others reduce memory traffic or sequential execution cost.

#table(
  columns: (1.4fr, 1.7fr, 2.1fr),
  inset: 6pt,
  [*Approach*], [*Primary target*], [*Important limitation*],
  [MQA / GQA], [KV-cache storage and bandwidth], [Less diversity among key-value heads],
  [Linear / low-rank attention], [Long-context attention work], [Similarity or token-compression error],
  [TFLA], [Linear-RNN GPU IO and kernel intensity], [Not an ordinary softmax replacement],
  [MoE], [Active compute at large total capacity], [Expert memory, routing, communication],
  [Quantization], [Bit width, memory, low-precision arithmetic], [Error, outliers, device kernels],
  [Structured pruning], [Dense matrix dimensions], [Capacity loss and recovery cost],
  [Unstructured pruning], [Stored nonzeros and sparse arithmetic], [Irregular access and sparse kernels],
  [Knowledge distillation], [Student quality at a smaller serving budget], [Teacher supervision and training expense],
  [Low-rank weights], [Unique weight parameters and factorized operations], [Reconstruction error and factor overhead],
  [Parameter sharing], [Unique stored parameters], [Repeated compute remains; reduced specialization],
)

== Deployment-Oriented Combinations

=== Long Context

The long-context problem has at least three separate parts: *position generalization*, *attention compute*, and *information retrieval fidelity*.

A RoPE extension such as PI or YaRN changes the positions used by attention but does not change the quadratic complexity of softmax attention. Kernel or low-rank attention changes the computation, but does not guarantee accurate retrieval from arbitrarily long contexts.

A practical design chooses one positional strategy, then one compatible attention mechanism, and evaluates both training and autoregressive execution. If a kernel-based mechanism is used, the effective state dimension and precision should be measured in addition to nominal $O(n)$ cost.

*Remark:* Positional extrapolation and computational complexity are different bottlenecks; success on one does not imply success on the other.

=== Fast Responses

For interactive generation, *per-token decoding latency* may dominate rather than full-sequence training FLOPs.

A smaller distilled backbone reduces the dense compute per output token. MQA/GQA can reduce reading KV-cache states, while quantization reduces weight bandwidth. Structured pruning may shorten dense operations, but a dynamic router or probe may introduce additional dispatch overhead.

*Remark:* Measure end-to-end token latency under realistic batch sizes, not only theoretical FLOPs or isolated kernel microbenchmarks.

=== Edge Devices

When device memory is limited, the first question is whether model weights, runtime activations, and KV caches *fit simultaneously*.

Low-bit weight quantization primarily helps parameter storage. GQA helps KV-cache storage, especially with long contexts. Selective sharing or structured pruning can further reduce the footprint, while distillation may recover quality in a smaller model.

*Remark:* Compression methods must match the accelerator's supported formats and kernels. A smaller serialized checkpoint is not enough to establish faster serving.

=== Accuracy-First Systems

If quality is the binding requirement, evaluate each architectural or compression change in isolation before stacking them. Low-bit attention or aggressive sparsity may especially harm exact retrieval, rare tokens, code, or long-context behavior even when average perplexity changes little.

Start with relatively gentle precision reduction and a KV-sharing strategy that retains enough key-value groups. Add more aggressive compression only when representative evaluations justify it.

*Remark:* The important objective is the *joint quality-latency-memory trade-off* on the target workload, not the largest possible compression percentage.

= Key Takeaways

- *Algorithmic complexity and hardware efficiency are not the same thing.* TFLA optimizes the execution of linear-RNN kernels; it does not create an exact softmax identity
- *Attention has multiple independent bottlenecks.* MQA/GQA reduce KV traffic, kernel methods approximate similarity, and Linformer/Luna compress interactions through shorter intermediate sequences
- *MoE increases total capacity without activating every expert for every token.* Routing, capacity balance, communication, and stored expert weights remain costs
- *Quantization techniques differ in the source of their accuracy.* GPTQ compensates output error, AWQ uses activation salience, SmoothQuant transfers difficulty across operands, and rotation/codebook methods reshape the representation before quantization
- *Pruning can remove weights, channels, activations, or interactions.* Their masks can be fixed, token-dependent, task-dependent, or batch-dependent, and these choices affect realizable speedups
- *Knowledge distillation is more than matching logits.* Different methods choose different teacher information, distribution divergences, and training-sequence distributions
- *Low-rank factorization and parameter sharing target different redundancy.* Low-rank factors reduce the size of a matrix representation, while sharing reduces the number of distinct matrices across layers
- *Always evaluate the deployed system.* Real improvements depend on memory movement, kernels, context length, batch size, hardware, and downstream quality
