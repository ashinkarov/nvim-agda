module Definitions where

open import Lib

data 𝔹 : Set where
  tt ff : 𝔹

_∧_ : 𝔹 → 𝔹 → 𝔹
tt ∧ y = y
ff ∧ y = ff

f : 𝔹 → 𝔹
f x = x ∧ tt  -- a comment

u : Unit
u = unit
