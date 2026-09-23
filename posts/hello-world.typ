#import "../typst/template.typ": *
#show: article.with(
  title: "最小二乘问题的梯度",
  date: "2026-09-23",
  description: "最小二乘目标函数及其梯度。",
  category: "Optimization",
)

= 目标函数

给定矩阵 $A$ 和向量 $b$，最小二乘目标函数为

$ f(x) = 1/2 norm(A x - b)^2 $

它的梯度为

$
  nabla f(x) = A^T (A x - b)
$

== Python 实现

输入为 NumPy 数组时，可以这样计算：

```python
def gradient(A, x, b):
    residual = A @ x - b
    return A.T @ residual
```

#definition[梯度][梯度指出函数增长最快的方向，沿负梯度移动可以寻找较小的函数值。]

== 示意图

下图中的箭头表示沿负梯度方向移动。

#image("../assets/gradient.svg", alt: "凸函数曲线上的点沿负梯度方向向最低点移动")
