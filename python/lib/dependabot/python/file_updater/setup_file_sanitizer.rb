# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/python/file_updater"
require "dependabot/python/file_parser/setup_file_parser"

module Dependabot
  module Python
    class FileUpdater
      # Take a setup.py, parses it (carefully!) and then create a new, clean
      # setup.py using only the information which will appear in the lockfile.
      class SetupFileSanitizer
        extend T::Sig

        sig do
          params(
            setup_file: T.nilable(Dependabot::DependencyFile),
            setup_cfg: T.nilable(Dependabot::DependencyFile)
          ).void
        end
        def initialize(setup_file:, setup_cfg:)
          @setup_file = T.let(setup_file, T.nilable(Dependabot::DependencyFile))
          @setup_cfg = T.let(setup_cfg, T.nilable(Dependabot::DependencyFile))
          @install_requires_array = T.let(nil, T.nilable(T::Array[String]))
          @setup_requires_array = T.let(nil, T.nilable(T::Array[String]))
          @extras_require_hash = T.let(nil, T.nilable(T::Hash[String, T::Array[String]]))
          @parsed_setup_file = T.let(nil, T.nilable(Dependabot::FileParsers::Base::DependencySet))
        end

        sig { returns(String) }
        def sanitized_content
          # The part of the setup.py that Pipenv cares about appears to be the
          # install_requires. A name and version are required by don't end up
          # in the lockfile.
          content =
            "from setuptools import setup\n\n" \
            "setup(name=\"#{package_name}\",version=\"0.0.1\"," \
            "install_requires=#{install_requires_array.to_json}," \
            "extras_require=#{extras_require_hash.to_json}"

          content += ',setup_requires=["pbr"],pbr=True' if include_pbr?
          content + ")"
        end

        private

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        attr_reader :setup_file

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        attr_reader :setup_cfg

        sig { returns(T::Boolean) }
        def include_pbr?
          setup_requires_array.any? { |d| d.start_with?("pbr") }
        end

        sig { returns(T::Array[String]) }
        def install_requires_array
          @install_requires_array ||=
            parsed_setup_file.dependencies.filter_map do |dep|
              first = T.must(dep.requirements.first)
              next unless first[:groups]
                          .include?("install_requires")

              dep.name + first[:requirement].to_s
            end
        end

        sig { returns(T::Array[String]) }
        def setup_requires_array
          @setup_requires_array ||=
            parsed_setup_file.dependencies.filter_map do |dep|
              first = T.must(dep.requirements.first)
              next unless first[:groups]
                          .include?("setup_requires")

              dep.name + first[:requirement].to_s
            end
        end

        sig { returns(T::Hash[String, T::Array[String]]) }
        def extras_require_hash
          @extras_require_hash ||=
            begin
              hash = {}
              parsed_setup_file.dependencies.each do |dep|
                first = T.must(dep.requirements.first)
                first[:groups].each do |group|
                  next unless group.start_with?("extras_require:")

                  hash[group.split(":").last] ||= []
                  hash[group.split(":").last] <<
                    (dep.name + first[:requirement].to_s)
                end
              end

              hash
            end
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def parsed_setup_file
          @parsed_setup_file ||=
            Python::FileParser::SetupFileParser.new(
              dependency_files: [
                setup_file&.dup&.tap { |f| f.name = "setup.py" },
                setup_cfg&.dup&.tap { |f| f.name = "setup.cfg" }
              ].compact
            ).dependency_set
        end

        sig { returns(String) }
        def package_name
          content = T.must(T.must(setup_file).content)
          match = content.match(/name\s*=\s*['"](?<package_name>[^'"]+)['"]/)
          match ? T.must(match[:package_name]) : "default_package_name"
        end
      end
    end
  end
end
