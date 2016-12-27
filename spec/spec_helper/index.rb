# frozen_string_literal: true
module Molinillo
  FIXTURE_DIR = Pathname.new('spec/resolver_integration_specs')
  FIXTURE_INDEX_DIR = FIXTURE_DIR + 'index'

  class TestIndex
    attr_accessor :specs
    include SpecificationProvider

    def self.from_fixture(fixture_name)
      File.open(FIXTURE_INDEX_DIR + (fixture_name + '.json'), 'r') do |fixture|
        sorted_specs = JSON.load(fixture).reduce(Hash.new([])) do |specs_by_name, (name, versions)|
          specs_by_name.tap do |specs|
            specs[name] = versions.map { |s| TestSpecification.new s }.sort_by(&:version)
          end
        end
        return new(sorted_specs)
      end
    end

    def initialize(specs_by_name)
      self.specs = specs_by_name
    end

    def requirement_satisfied_by?(requirement, _activated, spec)
      case requirement
      when TestSpecification
        requirement.version == spec.version
      when Gem::Dependency
        requirement.requirement.satisfied_by?(spec.version)
      end
    end

    def search_for(dependency)
      @search_for ||= {}
      @search_for[dependency] ||= begin
        prerelease = dependency_prerelease?(dependency)
        Array(specs[dependency.name]).select do |spec|
          (prerelease ? true : !spec.version.prerelease?) &&
            dependency.requirement.satisfied_by?(spec.version)
        end
      end
      @search_for[dependency].dup
    end

    def name_for(dependency)
      dependency.name
    end

    def dependencies_for(dependency)
      dependency.dependencies
    end

    def sort_dependencies(dependencies, activated, conflicts)
      dependencies.sort_by do |d|
        [
          activated.vertex_named(d.name).payload ? 0 : 1,
          dependency_prerelease?(d) ? 0 : 1,
          conflicts[d.name] ? 0 : 1,
          activated.vertex_named(d.name).payload ? 0 : search_for(d).count,
        ]
      end
    end

    private

    def dependency_prerelease?(dependency)
      dependency.prerelease?
    end
  end

  class BundlerIndex < TestIndex
    # Some bugs we want to write a regression test for only occurs when
    # Molinillo processes dependencies in a specific order for the given
    # index and demands. This sorting logic ensures we hit the repro case
    def sort_dependencies(dependencies, activated, conflicts)
      dependencies.sort_by do |dependency|
        name = name_for(dependency)
        [
          activated.vertex_named(name).payload ? 0 : 1,
          conflicts[name] ? 0 : 1,
          activated.vertex_named(name).payload ? 0 : search_for(dependency).count,
        ]
      end
    end
  end
end
