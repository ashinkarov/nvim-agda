module Modules where

module M where
  data T : Set where
    a b : T

module Only where
  module A where
  module B where

top : M.T
top = {! M !}
