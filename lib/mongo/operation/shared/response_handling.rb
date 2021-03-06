# Copyright (C) 2019-2020 MongoDB Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module Mongo
  module Operation

    # Shared behavior of response handling for operations.
    #
    # @api private
    module ResponseHandling

      private

      def validate_result(result, client, server)
        unpin_maybe(session) do
          add_error_labels(client, session) do
            add_server_diagnostics(server) do
              result.validate!
            end
          end
        end
      end

      # Adds error labels to exceptions raised in the yielded to block,
      # which should perform MongoDB operations and raise Mongo::Errors on
      # failure. This method handles network errors (Error::SocketError)
      # and server-side errors (Error::OperationFailure); it does not
      # handle server selection errors (Error::NoServerAvailable), for which
      # labels are added in the server selection code.
      def add_error_labels(client, session)
        begin
          yield
        rescue Mongo::Error::SocketError => e
          if session && session.in_transaction? && !session.committing_transaction?
            e.add_label('TransientTransactionError')
          end
          if session && session.committing_transaction?
            e.add_label('UnknownTransactionCommitResult')
          end

          maybe_add_retryable_write_error_label!(e, client, session)

          raise e
        rescue Mongo::Error::SocketTimeoutError => e
          maybe_add_retryable_write_error_label!(e, client, session)
          raise e
        rescue Mongo::Error::OperationFailure => e
          if session && session.committing_transaction?
            if e.write_retryable? || e.wtimeout? || (e.write_concern_error? &&
                !Session::UNLABELED_WRITE_CONCERN_CODES.include?(e.write_concern_error_code)
            ) || e.max_time_ms_expired?
              e.add_label('UnknownTransactionCommitResult')
            end
          end

          maybe_add_retryable_write_error_label!(e, client, session)

          raise e
        end
      end

      # Unpins the session if the session is pinned and the yielded to block
      # raises errors that are required to unpin the session.
      #
      # @note This method takes the session as an argument because this module
      #   is included in BulkWrite which does not store the session in the
      #   receiver (despite Specifiable doing so).
      #
      # @param [ Session | nil ] session Session to consider.
      def unpin_maybe(session)
        yield
      rescue Mongo::Error => e
        if session
          session.unpin_maybe(e)
        end
        raise
      end

      # Yields to the block and, if the block raises an exception, adds a note
      # to the exception with the address of the specified server.
      #
      # This method is intended to add server address information to exceptions
      # raised during execution of operations on servers.
      def add_server_diagnostics(server)
        yield
      rescue Error::SocketError, Error::SocketTimeoutError
        # Diagnostics should have already been added by the connection code,
        # do not add them again.
        raise
      rescue Error, Error::AuthError => e
        e.add_note("on #{server.address.seed}")
        raise e
      end

      private

      # A method that will add the RetryableWriteError label to an error if
      # any of the following conditions are true:
      #
      # If the error meets the criteria for a retryable error (i.e. has one
      #   of the retryable error codes or error messages)
      #
      # AND one of the following are true:
      #
      # The error occured during a commitTransaction or abortTransaction
      #   OR the error occured during a write outside of a transaction on a
      #   client that has the retry_writes set to true.
      #
      # If these conditions are met, the original error will be mutated.
      # If they're not met, the error will not be changed.
      #
      # @param [ Mongo::Error ] error The error to which to add the label.
      # @param [ Mongo::Client | nil ] client The client that is performing
      #   the operation.
      # @param [ Mongo::Session ] session The operation's session.
      #
      # @note The client argument is optional because some operations, such as
      #   end_session, do not pass the client as an argument to the execute
      #   method.
      def maybe_add_retryable_write_error_label!(error, client, session)
        in_transaction = session && session.in_transaction?
        committing_transaction = in_transaction && session.committing_transaction?
        aborting_transaction = in_transaction && session.aborting_transaction?
        modern_retry_writes = client && client.options[:retry_writes]
        legacy_retry_writes = client && !client.options[:retry_writes] &&
          client.max_write_retries > 0
        retry_writes = modern_retry_writes || legacy_retry_writes

        if (committing_transaction || aborting_transaction ||
            (!in_transaction && retry_writes)) && error.write_retryable?
          error.add_label('RetryableWriteError')
        end
      end
    end
  end
end
