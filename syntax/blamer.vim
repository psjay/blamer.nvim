if exists("b:current_syntax")
  finish
endif

" Define the main regions
syn match BlamerGitHash "^[0-9a-f]\{7,8\}\|^Not Committed" nextgroup=BlamerSeparator1 skipwhite
syn match BlamerSeparator1 "|" contained nextgroup=BlamerGitAuthor skipwhite
syn match BlamerGitAuthor "[^|]\+" contained nextgroup=BlamerSeparator2 skipwhite
syn match BlamerSeparator2 "|" contained nextgroup=BlamerGitDate skipwhite
syn match BlamerGitDate "[^|]\+" contained nextgroup=BlamerSeparator3 skipwhite
syn match BlamerSeparator3 "|" contained nextgroup=BlamerGitMessage skipwhite
syn match BlamerGitMessage ".*$" contained

" Link the syntax groups to highlight groups
hi def link BlamerSeparator1 Delimiter
hi def link BlamerSeparator2 Delimiter
hi def link BlamerSeparator3 Delimiter
hi def link BlamerGitHash Identifier
hi def link BlamerGitAuthor Type
hi def link BlamerGitDate String
hi def link BlamerGitMessage Comment

let b:current_syntax = "blamer"
