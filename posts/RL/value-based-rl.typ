#import "../../typst/template.typ": *
#show: article.with(title: "Value-Based RL")

Value-based RL tries to figure out $V(s)$ or $Q(s, a)$. The optimal policy is simply choosing the action with the largest $Q$. Value-based RL applies to cases with finite/infinite state spaces and finite action spaces, since finding the maximum of all $Q(s, a)$ is only feasible when the action space is finite.

= Value Iteration
In model-based RL, we know the environment model i.e. the transition dynamics and the reward function. In this case, we don't need to interact with the environment.

Using the Bellman Optimality Equation,
$ V (s) <- max_a (r (s,a) + gamma EE_(s^') [V (s^')]) $
We iterate $V$ until convergence to get $V^*$ corresponding to the optimal policy.

= Q-Learning
In model-free RL, we do not know the environment model. We interact with the environment to get sample trajectorys to approximate the expectation.
$ Q (s_t,a_t) arrow.l Q (s_t,a_t) + alpha delta_t $
$ delta_t = y_t-Q (s_t,a_t) $
$ y_t = r(s_t, a_t) + gamma max_(a_(t+1)) Q (s_(t+1),a_(t+1)) $
Here $delta_t$ is the TD error, where $y_t$ is the target and $Q(s_t, a_t)$ is the original prediction. $y_t$ represents the target we want our $Q$ to get close to. $y_t$ is the latest belief of the evaluation of $Q(s_t, a_t)$ we get by interacting with the environment, so we want to update the original $Q$ to get closer to $y_t$.
- If $y_t > Q(s_t, a_t)$, the original prediction is too pessimistic, so we want $Q$ to increase.
- If $y_t < Q(s_t, a_t)$, the original prediction is too optimistic, so we want $Q$ to decrease.

There is an another approach to understanding the method. The above iteration is equivalent to minimizing the loss function

$ L(Q) = 1/2 delta_t^2 $

Then we use gradient descent. Note that we freeze $y_t$ during backpropogation, treating it as a constant target.
$ nabla_Q L(Q) = -delta_t $
$ Q (s_t,a_t) arrow.l Q (s_t,a_t) - alpha nabla_Q L(Q) = Q (s_t,a_t) + alpha delta_t $

The loss function is intuitively meaningful because it is exactly Bellman error i.e. the difference between the left side and the right side of Bellman Optimality Equation. Bellman error reflects whether our policy is good or bad. When Bellman error equals to $0$, the policy is optimal.

As a result, Q-learning can also be interpreted as minimizing Bellman error through gradient descent.

We usually use the $epsilon$-greedy policy to balance choosing the seemingly optimal action and exploring other actions that might be even better.
= SARSA
SARSA is used to evaluate a policy.

SARSA is very similar to Q-learning except
$ y_t = r(s_t, a_t) + gamma Q (s_(t+1),a_(t+1)) $

We can see that when computing the target, Q-learning always uses the maximum no matter which action is actually taken while SARSA uses the action that is actually taken. This is because SARSA aims to evaluate the policy instead of finding an optimal policy. Evaluating a policy requires being faithful to the action taken by the policy while finding an optimal policy requires choosing the optimal action at any time corresponding to taking the maximum.

This means SARSA is *on-policy* while Q-learning is *off-policy*.

SARSA can alse be used to find the optimal policy. For example, we can use SARSA to evaluate the $epsilon$-greedy policy and gradually decrease $epsilon$ to $0$.

= Monte Carlo
Monte Carlo uses the full trajectory return $G_t$ to give the target $y_t$. Monte Carlo is used to evaluate a policy.
$ L(V) = 1/2 delta_t^2 $
$ delta_t = y_t - V(s_t) $
$ y_t = G_t = sum_(k=0)^(T - t - 1) gamma^k r(s_(t + k), a_(t + k)) $
$ V (s_t) arrow.l V (s_t) + alpha delta_t $
= Temporal-Difference Learning
Temporal-difference learning is very similar to Monte Carlo except it uses *bootstrapping* instead of waiting for the entire episode to end. Like Monte Carlo, temporal-difference learning is used to evaluate a policy. One-step TD is the $V$ version of SARSA.

$ y_t = r(s_t, a_t) + gamma V (s_(t+1)) $

For n-step TD,
$ y_t = G_(t: t + n) = sum_(k=0)^(n-1) gamma^k r(s_(t + k), a_(t + k)) + gamma^n V(s_(t +n)) $
TD($lambda$) takes the weighted average of different n-step TD,
$ y_t = (1 - lambda) sum_(n=1)^infinity lambda^(n-1) G_(t: t + n) $
TD(0) is one-step TD, TD(1) is Monte Carlo.
= Deep Q-Network (DQN)

The above methods can only apply to finite state spaces, where $Q: cal(S) times cal(A) -> RR$ is a discrete mapping i.e. a vector. In the case of an infinite state space and a finite action space, $Q: cal(S) times cal(A) -> RR$ is a continuous mapping i.e. a function. Instead of using a table as the $Q$ vector, we now use a neural network as the $Q$ function.
$ L(theta) = 1/2 delta_t^2 $
$ delta_t = y_t-Q_theta (s_t,a_t) $
$ y_t = r(s_t, a_t) + gamma max_(a_(t+1)) Q_theta' (s_(t+1),a_(t+1)) $
$ theta arrow.l theta + alpha delta_t nabla_theta Q_theta (s_t, a_t) $
DQN uses a replay buffer to store the sampled trajectorys and randomly draw single-step transitions from it. Experience replay reuses samples and reduces temporal correlation within batches.

DQN uses an online network and a target network. If we use the same network to compute the prediction $Q(s_t, a_t)$ and the target $y_t$, learning $theta$ will change both the prediction $Q(s_t, a_t)$ and the target $y_t$. The prediction needs to converge to a moving target, which will cause unsteady training or even divergence. Using two networks will address this problem. For each $C$ steps, the target network's parameters $theta^'$ stays constant, giving constant targets while the online network's parameters $theta$ is updated, narrowing the gap between predictions and targets. After each $C$ steps, $theta^' <- theta$, the parameters of the target network are synced.
= Double DQN
In DQN, the target network both evaluates the action and chooses the optimal action in $max_(a_(t+1)) Q_theta' (s_(t+1),a_(t+1))$.
This causes the target network to inherently overestimate the target $y_t$, because it always chooses the action with the highest $Q$ so that the overestimated action will be more likely to be chosen while the underestimated action will be less likely to be chosen.
As a result, the online network will also be inclined to give overestimated $Q$ because the target itself is inaccurate.

Double DQN separates action selection from evaluation.
$ L(theta) = 1/2 delta_t^2 $
$ delta_t = y_t-Q_theta (s_t,a_t) $
$ y_t = r(s_t, a_t) + gamma Q_theta' (s_(t+1), "argmax"_(a_(t+1)) Q_theta (s_(t+1),a_(t+1)) ) $
$ theta arrow.l theta + alpha delta_t nabla_theta Q_theta (s_t, a_t) $

The online network chooses the action and the target network evaluates the action. This reduces the maximization bias because the online network doesn't know whether the target network thinks the action is good or bad. So the positive feedback loop of overestimation will be surpressed.
= Dueling DQN

DQN directly estimates $Q$ of different actions. However, this does not utilize the internal structure of different actions' $Q$s given a state.

The value of a state-action pair $Q(s_t, a_t)$ consists of two parts: the value of the state per se $V(s_t)$ and the advantage $A(s_t, a_t)$ the action brings. For example, a large $Q(s_t, a_t)$ does not necessarily imply that the model chooses a very good action. It is also possible that the state per se is so good that taking any action will be ideal.

Dueling DQN uses two networks to respectively predict $Q$ and $A$, introducing a reasonable inductive bias.
$ L(theta) = 1/2 delta_t^2 $
$ delta_t = y_t-Q_theta (s_t,a_t) $
$ y_t = r(s_t, a_t) + gamma max_(a_(t+1)) Q_theta' (s_(t+1),a_(t+1)) $
$ Q_theta (s_t, a_t) = V_theta_V (s_t) + tilde(A)_theta_A (s_t, a_t) $
$ tilde(A)_theta_A (s_t, a_t) = A_theta_A (s_t, a_t) - 1/abs(cal(A)) sum_(a in cal(A)) A_theta_A (s_t, a) $
$ theta_V arrow.l theta_V + alpha delta_t nabla_theta_V V_theta_V (s_t) $
$ theta_A arrow.l theta_A + alpha delta_t nabla_theta_A tilde(A)_theta_A (s_t, a_t) $

$A$ is normalized by subtracting the mean since the decomposition of $V$ and $A$ is not unique.
We want $V$ to be the mean of $Q$ and the mean of $A$ to be $0$.
