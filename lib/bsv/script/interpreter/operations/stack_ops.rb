# frozen_string_literal: true

module BSV
  module Script
    class Interpreter
      module Operations
        module StackOps
          private

          # OP_TOALTSTACK: move top of data stack to alt stack
          def op_toaltstack
            @astack.push_bytes(@dstack.pop_bytes)
          end

          # OP_FROMALTSTACK: move top of alt stack to data stack
          def op_fromaltstack
            @dstack.push_bytes(@astack.pop_bytes)
          end

          # OP_IFDUP: duplicate top if truthy
          def op_ifdup
            val = @dstack.peek_bytes(0)
            @dstack.push_bytes(val.dup) if Stack.cast_bool(val)
          end

          # OP_DEPTH: push stack depth as number
          def op_depth
            @dstack.push_int(ScriptNumber.new(@dstack.depth))
          end

          # OP_DROP
          def op_drop
            @dstack.drop_n(1)
          end

          # OP_2DROP
          def op_2drop
            @dstack.drop_n(2)
          end

          # OP_DUP
          def op_dup
            @dstack.dup_n(1)
          end

          # OP_2DUP
          def op_2dup
            @dstack.dup_n(2)
          end

          # OP_3DUP
          def op_3dup
            @dstack.dup_n(3)
          end

          # OP_NIP: remove second-to-top
          def op_nip
            @dstack.nip_n(1)
          end

          # OP_OVER
          def op_over
            @dstack.over_n(1)
          end

          # OP_2OVER
          def op_2over
            @dstack.over_n(2)
          end

          # OP_PICK: copy item at depth n to top
          def op_pick
            idx = @dstack.pop_int.to_i32
            @dstack.pick_n(idx)
          end

          # OP_ROLL: move item at depth n to top
          def op_roll
            idx = @dstack.pop_int.to_i32
            @dstack.roll_n(idx)
          end

          # OP_ROT
          def op_rot
            @dstack.rot_n(1)
          end

          # OP_2ROT
          def op_2rot
            @dstack.rot_n(2)
          end

          # OP_SWAP
          def op_swap
            @dstack.swap_n(1)
          end

          # OP_2SWAP
          def op_2swap
            @dstack.swap_n(2)
          end

          # OP_TUCK
          def op_tuck
            @dstack.tuck
          end
        end
      end
    end
  end
end
