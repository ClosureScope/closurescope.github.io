#import "../../typst/template.typ": *
#show: article.with(
  title: "单调栈",
)

单调栈即栈内元素具有单调性的栈。

其能在$O(n)$时间内找出数组每个元素右（左）侧第一个更大（小）元素。

以找出右侧第一个更大元素的下标为例，有两种思路：

*从右向左遍历*

从右向左遍历，栈内维护可能成为答案的元素。

注意到栈内元素严格单调减，因为若有递增或相等的情况，即`stack = [..., a, b, ...]`且满足$a <= b$，则先被压入的`a`不可能成为某个元素右侧第一个更大元素，因为后压入的`b`也一定是该元素右侧更大的元素且比`a`更加靠前，故`a`不可能是答案，矛盾，故栈内元素严格单调减。

每个元素的答案在该元素被压栈时决定，其即将被压入时的栈顶元素即为答案，因为在其即将被压入时，我们已经遍历了其右侧所有的元素，覆盖了所有可能的答案，最近的可能答案也即栈顶元素就是最终答案。


```python
def right_greater(nums: list[int]) -> list[int]:
    n = len(nums)
    right = [n] * n
    st = []
    for i in range(n - 1, -1, -1):
        while st and nums[st[-1]] <= nums[i]: 
            st.pop()
        if st:
            right[i] = st[-1]
        st.append(i)
    return right
```

*从左向右遍历*

从左向右遍历，栈内维护等待答案的元素。

注意到栈内元素单调减，因为若有递增的情况，即`stack = [..., a, b, ...]`且满足$a < b$，则先被压入的`a`右侧第一个更大元素就是`b`，`a`不需要等待答案，矛盾，故栈内元素单调减。

每个元素的答案在该元素被弹出时决定，此时正在处理的元素即为答案，因为出栈代表该元素从等待答案转变成不再等待答案，此时正在处理的元素一定比该元素大，并且由于栈的单调性和从左向右遍历，处理中元素一定是第一个更大元素，故其即为答案。

```python
def right_greater(nums: list[int]) -> list[int]:
    n = len(nums)
    right = [n] * n
    st = []
    for i in range(n):
        while st and nums[st[-1]] < nums[i]:
            right[st.pop()] = i
        st.append(i)
    return right
```
