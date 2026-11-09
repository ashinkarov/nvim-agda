module Problems where

data 𝔹 : Set where
  tt ff : 𝔹

record R : Set where
  field
    x : 𝔹
open R

incomplete : 𝔹 → 𝔹
incomplete tt = ff

unreachable : 𝔹 → 𝔹
unreachable tt = tt
unreachable ff = ff
unreachable tt = ff
