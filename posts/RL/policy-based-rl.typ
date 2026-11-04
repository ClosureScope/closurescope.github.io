#import "../../typst/template.typ": *
#show: article.with(title: "Policy-Based RL")

Instead of tring to figure out $V$ or $Q$, policy-based RL tries to directly learn the optimal policy

= REINFORCE

We want to maximize the objective function
$ J(theta) = EE_tau [G_0] $
Using the policy gradient theorem,
$
  nabla_theta J (theta)
  =
  EE_tau [
    sum_(t=0)^(T-1)
    gamma^t
    G_t
    nabla_theta
    log pi_theta (a_t | s_t)]
$
We use Monte Carlo to approximate the expectation,
$
  nabla_theta J (theta)
  =
  sum_(t=0)^(T-1)
  gamma^t
  G_t
  nabla_theta
  log pi_theta (a_t | s_t)
$
$
  theta <- theta + alpha sum_(t=0)^(T-1)
  gamma^t
  G_t
  nabla_theta
  log pi_theta (a_t | s_t)
$

= Actor-Critic
Actor-Critic uses an actor network to learn $pi(a | s)$ and a critic network to learn $V(s)$.

The actor takes action
$ a_t tilde pi_theta_pi (a | s_t) $
The actor wants to maximize
$ J(theta_pi) = Q(s_t, a_t) = r(s_t, a_t) + gamma V_theta_V (s_(t+1)) $
to find the optimal policy.

The critic wants to minimize
$ L(theta_V) = 1/2 delta_t^2 $
to accurately evaluate each state.
$ delta_t = A(s_t, a_t) = y_t - V_theta_V (s_t) $
$ y_t = Q(s_t, a_t) = r(s_t, a_t) + gamma V_theta_V (s_(t+1)) $

Using the policy gradient theorem,
$ theta_pi <- theta_pi + alpha_pi Q(s_t, a_t) nabla_theta_pi log pi_theta_pi (a_t | s_t) $


Policy gradient theorem allows us to subtract a baseline. Here we choose $V_theta_V (s_t)$ as the baseline.
$ theta_pi <- theta_pi + alpha_pi A(s_t, a_t) nabla_theta_pi log pi_theta_pi (a_t | s_t) $
$nabla_theta_pi log pi_theta_pi (a_t | s_t)$ points to the direction of ascent of $pi_theta_pi (s_t, a_t)$.
- If $A(s_t, a_t) > 0$, $theta_pi$ is updated to the direction that increases $pi_theta_pi (s_t, a_t)$, making the good action more likely to be chosen.
- If $A(s_t, a_t) < 0$, $theta_pi$ is updated to the direction that decreases $pi_theta_pi (s_t, a_t)$, making the bad action less likely to be chosen.
$theta_V$ is updated the same way as in value-based methods.
$ theta_V <- theta_V + alpha_V delta_t nabla_theta_V V_theta_V (s_t) $

Actor-Critic can learn from single-step transitions since we can use $V_theta_V (s_(t+1))$ to estimate the remaining return. This greatly improves sample efficiency. Moreover, using $A(s_t, s_t)$ instead of return-related measures like $G_t$ or $Q(s_t, a_t)$ reduces variance.

= Trust Region Policy Optimization (TRPO)
We do not want the policy to be changed too drastically each update. TRPO constrains the change of the policy.

The actor wants to maximize
$ J(theta) = EE_(s_t, a_t) [rho_t (theta) A^(pi_theta_"old") (s_t, a_t)] $
$ rho_t (theta) = (pi_theta (a_t | s_t))/(pi_theta_"old" (a_t | s_t)) $

This surrogate objective is reasonable because
- If $A^(pi_theta_"old") (s_t, a_t) > 0$, $a_t$ is good, maximizing $J$ requires maximizing $rho$, thus $pi_theta (a_t | s_t)$ increases.
- If $A^(pi_theta_"old") (s_t, a_t) < 0$, $a_t$ is bad, maximizing $J$ requires minimizing $rho$, thus $pi_theta (a_t | s_t)$ decreases.

The update is constrained by
$ EE_s [D_"KL" (pi_theta_"old" (dot | s) || pi_theta (dot | s)))] <= delta $

TRPO still uses a critic to predict $V$.
= Proximal Policy Optimization (PPO)

PPO replaces the constrained problem by maximizing the surrogate objective
$
  J (theta) = EE_(s_t, a_t) [min(rho_t (theta) A^(pi_theta_"old") (s_t, a_t), "clip"(rho_t (theta),1-epsilon,1+epsilon) A^(pi_theta_"old") (s_t, a_t))]
$

For positive advantage, increasing the ratio beyond $1+epsilon$ gives no further gain. For negative advantage, decreasing it below $1-epsilon$ gives no further gain.
