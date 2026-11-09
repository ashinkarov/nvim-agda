module Missing where

open import Agda.Builtin.Nat

data Fin : Nat → Set where
  zero : {n : Nat} → Fin (suc n)

test : (x y : Nat) → Fin x → Fin y → Set
test x y a b = Nat

-- A missing definition and an unsolved meta (n of the first zero).
boo : (n : Nat) → test _ (suc n) zero zero
