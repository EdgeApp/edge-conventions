#!/bin/bash

# Check if enough arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 \"<command-to-run>\" <commit-hash>"
    exit 1
fi

COMMAND_TO_RUN="$1"
TARGET_COMMIT="$2"

# Start the interactive rebase with an inline function definition
GIT_SEQUENCE_EDITOR=: git rebase -i --exec "bash -c ' \
    COMMAND_TO_RUN=\"$COMMAND_TO_RUN\"; \
    run_command_and_check() { \
        eval \"\$COMMAND_TO_RUN\"; \
        COMMAND_EXIT_STATUS=\$?; \
        if [ \$COMMAND_EXIT_STATUS -ne 0 ]; then \
            echo \"Command failed with exit status \$COMMAND_EXIT_STATUS\"; \
            exit \$COMMAND_EXIT_STATUS; \
        fi; \
        if [ -n \"\$(git status --porcelain)\" ]; then \
            git add .; \
            git commit --fixup HEAD; \
        fi; \
    }; \
    run_command_and_check' \
" $TARGET_COMMIT

if [ $? -ne 0 ]; then
    echo "Rebase encountered an error. Resolve conflicts/errors and continue with 'git rebase --continue'."
    exit 1
fi

echo "Rebase completed successfully."