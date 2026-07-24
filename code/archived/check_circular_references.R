#!/usr/bin/env Rscript
# Circular Reference Detection Tool
# =================================
# Analyzes R codebase for circular dependencies and references

library(dplyr)

cat("=== CIRCULAR REFERENCE ANALYSIS ===\n")

# Track all source() calls and their relationships
source_dependencies <- list()

# Function to extract source calls from a file
extract_source_calls <- function(file_path) {
  if (!file.exists(file_path)) {
    return(character(0))
  }

  content <- readLines(file_path, warn = FALSE)

  # Find source() patterns
  source_patterns <- grep('source\\s*\\(', content, value = TRUE)

  sources <- character(0)
  for (pattern in source_patterns) {
    # Extract file path from source() call
    matches <- regmatches(pattern, gregexpr('source\\s*\\(\\s*["\']([^"\']+)["\']', pattern))
    if (length(matches[[1]]) > 0) {
      # Extract just the filename part
      file_ref <- sub('source\\s*\\(\\s*["\']([^"\']+)["\'].*', '\\1', matches[[1]][1])
      sources <- c(sources, file_ref)
    }
  }

  return(sources)
}

# Get all R files in the project
r_files <- list.files(".", pattern = "\\.R$", recursive = TRUE, full.names = TRUE)
r_files <- r_files[!grepl("/deprecated/", r_files)]  # Skip deprecated files

cat(sprintf("Analyzing %d R files for circular references...\n\n", length(r_files)))

# Build dependency map
for (file in r_files) {
  file_name <- basename(file)
  sources <- extract_source_calls(file)

  if (length(sources) > 0) {
    source_dependencies[[file_name]] <- sources
    cat(sprintf("📄 %s sources: %s\n", file_name, paste(sources, collapse = ", ")))
  }
}

cat("\n=== DEPENDENCY ANALYSIS ===\n")

# Check for circular references
circular_refs <- list()

for (file_name in names(source_dependencies)) {
  dependencies <- source_dependencies[[file_name]]

  # Check if any dependency also sources this file
  for (dep in dependencies) {
    dep_basename <- basename(dep)

    if (dep_basename %in% names(source_dependencies)) {
      dep_sources <- source_dependencies[[dep_basename]]

      # Check if the dependency sources back to this file
      if (file_name %in% basename(dep_sources) || file_name %in% dep_sources) {
        circular_refs[[paste(file_name, "↔", dep_basename)]] <- list(
          file1 = file_name,
          file2 = dep_basename,
          type = "direct"
        )
        cat(sprintf("🔄 DIRECT CIRCULAR: %s ↔ %s\n", file_name, dep_basename))
      }
    }
  }
}

# Check for indirect circular references (A → B → C → A)
cat("\n=== CHECKING FOR INDIRECT CIRCULAR REFERENCES ===\n")

find_circular_path <- function(start_file, current_file, visited, path) {
  if (current_file %in% visited) {
    if (current_file == start_file) {
      return(path)  # Found circular reference
    } else {
      return(NULL)  # Different cycle, not what we're looking for
    }
  }

  if (!current_file %in% names(source_dependencies)) {
    return(NULL)  # No dependencies
  }

  new_visited <- c(visited, current_file)
  new_path <- c(path, current_file)

  for (dep in source_dependencies[[current_file]]) {
    dep_basename <- basename(dep)
    result <- find_circular_path(start_file, dep_basename, new_visited, new_path)
    if (!is.null(result)) {
      return(result)
    }
  }

  return(NULL)
}

indirect_circulars <- list()

for (file_name in names(source_dependencies)) {
  circular_path <- find_circular_path(file_name, file_name, character(0), character(0))

  if (!is.null(circular_path) && length(circular_path) > 2) {
    path_str <- paste(circular_path, collapse = " → ")
    indirect_circulars[[path_str]] <- circular_path
    cat(sprintf("🔄 INDIRECT CIRCULAR: %s → %s\n", path_str, file_name))
  }
}

# Check for function-level circular calls within files
cat("\n=== CHECKING FOR FUNCTION-LEVEL CIRCULAR REFERENCES ===\n")

function_calls <- list()

for (file in r_files) {
  file_name <- basename(file)
  content <- readLines(file, warn = FALSE)

  # Find function definitions
  func_defs <- grep('^[a-zA-Z_][a-zA-Z0-9_]*\\s*<-\\s*function', content, value = TRUE)

  if (length(func_defs) > 0) {
    for (func_def in func_defs) {
      func_name <- sub('^([a-zA-Z_][a-zA-Z0-9_]*)\\s*<-.*', '\\1', func_def)
      func_name <- trimws(func_name)

      if (nchar(func_name) > 0) {
        # Look for calls to other functions in this file
        func_calls <- character(0)
        for (line in content) {
          # Find function calls (basic pattern)
          calls <- regmatches(line, gregexpr('[a-zA-Z_][a-zA-Z0-9_]*\\s*\\(', line))
          if (length(calls[[1]]) > 0) {
            for (call in calls[[1]]) {
              called_func <- sub('\\s*\\(.*', '', call)
              called_func <- trimws(called_func)
              if (nchar(called_func) > 0 && called_func != func_name) {
                func_calls <- c(func_calls, called_func)
              }
            }
          }
        }

        if (length(func_calls) > 0) {
          function_calls[[paste(file_name, func_name, sep = "::")]] <- unique(func_calls)
        }
      }
    }
  }
}

# Look for function-level circular references
func_circulars <- 0
for (func_key in names(function_calls)) {
  file_func <- strsplit(func_key, "::")[[1]]
  file_name <- file_func[1]
  func_name <- file_func[2]

  calls <- function_calls[[func_key]]

  # Check if this function calls itself (direct recursion)
  if (func_name %in% calls) {
    cat(sprintf("🔄 RECURSIVE FUNCTION: %s::%s calls itself\n", file_name, func_name))
    func_circulars <- func_circulars + 1
  }

  # Check for mutual recursion within same file
  for (call in calls) {
    reverse_key <- paste(file_name, call, sep = "::")
    if (reverse_key %in% names(function_calls)) {
      reverse_calls <- function_calls[[reverse_key]]
      if (func_name %in% reverse_calls) {
        cat(sprintf("🔄 MUTUAL RECURSION: %s::%s ↔ %s::%s\n", file_name, func_name, file_name, call))
        func_circulars <- func_circulars + 1
      }
    }
  }
}

# Check for exists() calls that might indicate circular loading issues
cat("\n=== CHECKING FOR DYNAMIC LOADING PATTERNS ===\n")

for (file in r_files) {
  file_name <- basename(file)
  content <- readLines(file, warn = FALSE)

  exists_patterns <- grep('exists\\s*\\(|if\\s*\\(.*exists', content, value = TRUE)

  if (length(exists_patterns) > 0) {
    cat(sprintf("⚠️  %s uses exists() - potential dynamic loading:\n", file_name))
    for (pattern in exists_patterns) {
      cat(sprintf("   %s\n", trimws(pattern)))
    }
  }
}

# Summary report
cat("\n=== CIRCULAR REFERENCE SUMMARY ===\n")

total_issues <- length(circular_refs) + length(indirect_circulars) + func_circulars

if (total_issues == 0) {
  cat("✅ NO CIRCULAR REFERENCES FOUND!\n")
  cat("✅ Codebase has clean dependency structure\n")
} else {
  cat(sprintf("⚠️  Found %d potential circular reference issues:\n", total_issues))
  cat(sprintf("   Direct circular imports: %d\n", length(circular_refs)))
  cat(sprintf("   Indirect circular imports: %d\n", length(indirect_circulars)))
  cat(sprintf("   Function-level circular calls: %d\n", func_circulars))
}

cat("\n=== RECOMMENDATIONS ===\n")

if (length(circular_refs) > 0) {
  cat("🔧 Fix direct circular imports by:\n")
  cat("   - Moving shared functions to a common utility file\n")
  cat("   - Using dependency injection instead of direct sourcing\n")
  cat("   - Restructuring code to eliminate bidirectional dependencies\n")
}

if (length(indirect_circulars) > 0) {
  cat("🔧 Fix indirect circular imports by:\n")
  cat("   - Creating a dependency graph and breaking cycles\n")
  cat("   - Moving common dependencies to base modules\n")
  cat("   - Using lazy loading or conditional sourcing\n")
}

if (func_circulars > 0) {
  cat("🔧 Function-level recursion found:\n")
  cat("   - Verify recursion has proper base cases\n")
  cat("   - Add depth limits to prevent stack overflow\n")
  cat("   - Consider iterative alternatives for deep recursion\n")
}

cat("\n=== DEPENDENCY GRAPH ===\n")
for (file_name in names(source_dependencies)) {
  deps <- source_dependencies[[file_name]]
  if (length(deps) > 0) {
    cat(sprintf("%s → %s\n", file_name, paste(basename(deps), collapse = ", ")))
  }
}

cat("\n🔍 Analysis complete.\n")
