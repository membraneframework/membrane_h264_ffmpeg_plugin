defmodule Membrane.Element.FFmpeg.H264.Parser.NALu do
  use Bunch
  alias Membrane.Buffer

  @nalu_types %{
                0 => :unspecified,
                1 => :non_idr,
                2 => :part_a,
                3 => :part_b,
                4 => :part_c,
                5 => :idr,
                6 => :sei,
                7 => :sps,
                8 => :pps,
                9 => :aud,
                10 => :end_of_seq,
                11 => :end_of_stream,
                12 => :filler_data,
                13 => :sps_extension,
                14 => :prefix_nal_unit,
                15 => :subset_sps,
                (16..18) => :reserved,
                19 => :auxiliary_non_part,
                20 => :extension,
                (21..23) => :reserved,
                (24..31) => :unspecified
              }
              |> Enum.flat_map(fn {k, v} -> k |> Bunch.listify() |> Enum.map(&{&1, v}) end)
              |> Map.new()

  def parse(access_unit) do
    {buffers, {au_info, _new_access_unit}} =
      access_unit
      |> extract_nalus()
      |> Enum.map_reduce({%{key_frame?: false}, new_access_unit?: true}, &parse_nalu/2)

    {buffers, au_info}
  end

  defp extract_nalus(access_unit) do
    access_unit
    |> :binary.matches([<<0, 0, 0, 1>>, <<0, 0, 1>>])
    |> Enum.chunk_every(2, 1, [{byte_size(access_unit), nil}])
    |> Enum.map(fn [{from, _}, {to, _}] -> :binary.part(access_unit, from, to - from) end)
  end

  defp parse_nalu(nalu, {access_unit_info, new_access_unit?: new_au}) do
    <<0::1, _nal_ref_idc::unsigned-integer-size(2), nal_unit_type::unsigned-integer-size(5),
      _rest::bitstring>> = unprefix(nalu)

    type = @nalu_types |> Map.fetch!(nal_unit_type)

    access_unit_info =
      access_unit_info
      |> Map.merge(
        case type do
          :idr -> %{key_frame?: true}
          _ -> %{}
        end
      )

    buffer = %Buffer{metadata: %{type: type, new_access_unit?: new_au}, payload: nalu}
    {buffer, {access_unit_info, new_access_unit?: false}}
  end

  defp unprefix(<<0, 0, 0, 1, nalu::binary>>), do: nalu
  defp unprefix(<<0, 0, 1, nalu::binary>>), do: nalu
end
