module Blocked where

data 𝔹 : Set where
  tt ff : 𝔹

G : 𝔹 → 𝔹
G tt = tt
G ff = tt

postulate
  R : 𝔹 → Set
  r : R tt
  f : (b : 𝔹) → R (G b) → 𝔹

k : 𝔹
k = f {! !} r
