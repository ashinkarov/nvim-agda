module Constraints where

data 𝔹 : Set where
  tt ff : 𝔹

postulate
  P : 𝔹 → Set
  p : P _

G : 𝔹 → 𝔹
G tt = tt
G ff = tt

postulate
  Q : 𝔹 → Set
  q : ∀ {x} → Q (G x)

r : Q tt
r = q

s : 𝔹
s = ?

t : P tt
t = ?
