module Give where

data 𝔹 : Set where
  tt ff : 𝔹

and : 𝔹 → 𝔹 → 𝔹
and a b = a

after : 𝔹 → 𝔹
after x = and ? ff  -- comment

twice : 𝔹 → 𝔹
twice x = and (and {! !} ff) {! !}

long : 𝔹 → 𝔹
long x = ?

data Two : 𝔹 → 𝔹 → Set where
  two : Two tt ff

solved : Two {! !} {! !}
solved = two
