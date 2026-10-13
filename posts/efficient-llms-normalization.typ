#import "../typst/template.typ": *
#show: article.with(
  title: "Efficient LLMs: Normalization",
  date: "2026-10-10",
  category: "LLM",
)


= LayerNorm, Post-LN, and Pre-LN

LayerNorm centers and rescales the features of each token:

$ "LN"(x) = gamma (x - mu) / sqrt(sigma^2 + epsilon) + beta $

The placement of normalization changes the residual path:

$ "Post-LN": quad x^' = "LN"(x + F(x)) $
$ "Pre-LN": quad x^' = x + F("LN"(x)) $

*Remark:* Post-LN can create unstable gradient scales in deep networks. Pre-LN preserves an explicit identity path and typically simplifies optimization. Neither removes the cost of normalization.

= Mix-LN

Use Post-LN in earlier layers and Pre-LN in later layers, with a depth-dependent transition.

*Remark:* Tries to combine stronger early gradient signals with stable deep-layer optimization.

= AdaNorm

Instead of learned affine gain and bias, AdaNorm applies an input-dependent multiplier to normalized features $y$. The scaling factor $phi(y)$ is detached during backpropagation.
$ y = (x - mu) / sqrt(sigma^2 + epsilon) $
$ phi(y) = C (1 - k y), quad z = phi(y) y $



*Remark:* Simplifies the affine portion of normalization and can improve convergence in evaluated settings. The positivity and scaling behavior of $phi$ must be controlled.

= ReZero

Remove normalization and learn a scalar gate for each residual branch:

$ x^' = x + alpha F(x), quad alpha = 0 " at initialization" $

*Remark:* Initially, the network is an identity mapping, facilitating stable deep optimization. Stability then depends on the learned residual scaling; this is a different approach from simplifying LayerNorm.

= nGPT

Normalize all vectors including embeddings, attending outputs, and MLP outputs to unit norm throughout the network:

$ hat(x) = x / norm(x)_2 $

*Remark:* Maintains stable output scaling and enable fast training without conventional LayerNorm or weight decay.

= GPT-2

Remove LayerNorm from a pretrained model and recover quality with further fine-tuning.

*Remark:* GPT-2 indicates that some trained models tolerate normalization removal surprisingly well. This does not establish that normalization is unnecessary during initial training.

= RMSNorm

Normalize by the root mean square, without subtracting the mean:

$ "RMSNorm"(x) = gamma x / sqrt(sigma^2 + epsilon) $

*Remark:* Cheaper than mean-centered LayerNorm and widely used in modern LLMs. It provides scale normalization rather than mean invariance.

= Dynamic Tanh (DyT)

Based on the observation that the behavior of LayerNorm closely resembles that of $tanh$, replace explicit mean/variance calculations with a learned scaled nonlinearity.

$ "DyT"(x) = gamma tanh(alpha x) + beta $

*Remark:* Offers a simple normalization alternative with competitive results on evaluated models.
