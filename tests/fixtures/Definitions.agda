module Definitions where

open import Lib

data 𝔹 : Set where
  tt ff : 𝔹

_∧_ : 𝔹 → 𝔹 → 𝔹
tt ∧ y = y
ff ∧ y = ff

f : 𝔹 → 𝔹
f x = x ∧ tt  -- like (Lib.unit)

u : Unit
u = unit

module M where
  if_then_else_ : 𝔹 → 𝔹 → 𝔹 → 𝔹
  if tt then x else y = x
  if ff then x else y = y

g : 𝔹 → 𝔹
g x = M.if_then_else_ x tt {! x !}

h : 𝔹 → 𝔹
h x = if x then ff else tt where open M
