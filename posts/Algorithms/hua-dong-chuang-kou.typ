#import "../../typst/template.typ": *
#show: article.with(
  title: "滑动窗口",
)

滑动窗口适合解决：

研究数组的子区间，窗口状态可增量维护

时间复杂度：$O(n)$

以下使用`left`, `right`来维护`[left, right]`的滑动窗口
= 定长滑动窗口
定长滑动窗口适合解决：

研究数组的子区间，窗口状态可增量维护，窗口长度固定

时间复杂度：$O(n)$

```python
def sliding_window(nums: list, k: int) -> Res:
    res = Res()
    state = State()
    for right in range(len(nums)): # 枚举右端点
        # 右端点进入窗口，使窗口状态包含右端点
        state.add(nums[right])

        left = right - k + 1
        if left < 0: # 第一个窗口还未形成
            continue
        
        # 此时窗口长度合法，更新答案
        res.update()

        # 左端点离开窗口，使窗口状态去除左端点
        state.remove(nums[left])

    return res
```

= 不定长滑动窗口

不定长滑动窗口适合解决：

研究数组的子区间，窗口状态可增量维护，窗口合法性对于区间包含关系具有单调性，关注合法性分界点的情况

时间复杂度：$O(n)$

== 越短越合法/求最长
```python
def sliding_window(nums: list) -> Res:
    res = Res()
    state = State()
    left = 0
    for right in range(len(nums)): # 枚举右端点，增长窗口
        # 右端点进入窗口，使窗口状态包含右端点
        state.add(nums[right])

        while (not check(state)): # 不合法时不断移动左端点，缩短窗口，直到合法
            # 左端点离开窗口，使窗口状态去除左端点
            state.remove(nums[left])
            left += 1
          
        # 此时窗口恰好合法，更新答案
        res.update()

    return res
```
若统计合法子区间个数，`res.update()`即为`res += right - left + 1`，因为此时`[left, right]`, `[left + 1, right]`, ..., `[right, right]`都是合法的。
== 越长越合法/求最短
```python
def sliding_window(nums: list) -> Res:
    res = Res()
    state = State()
    left = 0
    for right in range(len(nums)): # 枚举右端点，增长窗口
        # 右端点进入窗口，使窗口状态包含右端点
        state.add(nums[right])

        while (check(state)): # 合法时不断移动左端点，缩短窗口，直到不合法
            # 左端点离开窗口，使窗口状态去除左端点
            state.remove(nums[left])
            left += 1
        
        # 此时窗口恰好不合法，更新答案（注意恰好合法的窗口是左端点向左移动一格的窗口）
        res.update()

    return res
```
若统计合法子区间个数，`res.update()`即为`res += left`，因为此时`[left - 1, right]`, `[left - 2, right]`, ..., `[0, right]`都是合法的。
== 恰好型滑动窗口
恰好型滑动窗口可以转化为两个越短越合法或越长越合法。

如统计元素和恰好$= k$的子区间个数，可以转化为元素和$>= k$的子区间个数减去元素和$>= k + 1$的子区间个数。

