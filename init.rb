# frozen_string_literal: true

# Ulysses: the issue page and issue list, edited in place.
# Copyright (C) 2026 Peter Fitzgibbons
#
# This program is free software; you can redistribute it and/or modify it under the terms of the
# GNU General Public License as published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version. See LICENSE.

require_relative 'lib/redmine_ulysses/hooks'

Redmine::Plugin.register :redmine_ulysses do
  name 'Ulysses'
  author 'Peter Fitzgibbons'
  description 'Edit the issue page and the issue list in place'
  version '0.1.0'
  url 'https://github.com/pjfitzgibbons/redmine_ulysses'
  requires_redmine version_or_higher: '7.0.2'
end

# The plugin's pins join core's importmap: Turbo, the plugin's entry module, and its Stimulus
# controllers under controllers/, where core's index.js eager-loads them. Redmine runs this file
# again on each reload in development; drawing the same pins again changes nothing.
Rails.application.importmap.draw(File.join(__dir__, 'config/importmap.rb'))
