# frozen_string_literal: true

class AnonymousFeedbackController < ApplicationController
  # Diese Route soll öffentlich sein, obwohl das Forum Login erzwingt.
  # Welche before_action bei dir greift, hängt vom Setup ab – wir starten minimal
  # und passen im nächsten Schritt an, falls es noch zum Login redirectet.

  def index
    render :index
  end
end
